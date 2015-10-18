# Is used to write streamed ZIP archives into the provided IO-ish object.
# The output IO is never going to be rewound or seeked, so the output
# of this object can be coupled directly to, say, a Rack output.
#
# Allows for splicing raw files (for "stored" entries without compression)
# and splicing of deflated files (for "deflated" storage mode).
#
# For stored entries, you need to know the CRC32 (as a uint) and the filesize upfront,
# before the writing of the entry body starts.
#
# For compressed entries, you need to know the bytesize of the precompressed entry
# as well.
class ZipTricks::Streamer
  InvalidFlow = Class.new(StandardError)
  EntryBodySizeMismatch = Class.new(StandardError)
  
  # Possible states of the streamer
  STATES = [:before_entry, :in_entry_header, :in_entry_body, :in_central_directory, :closed]
  
  # Describes the possible state transitions. Is used primarily to prevent you (the devleoper)
  # from using the Streamer in an improper way - since the output IO can never be rewound,
  # a very strict sequence of method calls is needed to produce a valid ZIP archive
  TRANSITIONS = [
    [:before_entry, :in_entry_header],
    [:in_entry_header, :in_entry_body],
    [:in_entry_body, :in_entry_header],
    [:in_entry_body, :in_central_directory],
    [:in_central_directory, :closed]
  ]
  
  # Language encoding flag (EFS) bit (general purpose bit 11)
  EFS = 0b100000000000
  
  # Default general purpose flags for each entry.
  DEFAULT_GP_FLAGS = 0b00000000000
  
  # Creates a new Streamer on top of the given IO-ish object and yields it. Once the given block
  # returns, the Streamer will have it's `close` method called, which will write out the central
  # directory of the archive to the output.
  #
  # @param stream [IO] the destination IO for the ZIP (should respond to `tell` and `<<`)
  # @yield [Streamer] the streamer that can be written to
  def self.open(stream)
    archive = new(stream)
    yield(archive)
    archive.close
  end
  
  # Creates a new Streamer on top of the given IO-ish object.
  #
  # @param stream [IO] the destination IO for the ZIP (should respond to `tell` and `<<`)
  def initialize(stream)
    unless stream.respond_to?(:<<) && stream.respond_to?(:tell)
      raise "The stream should respond to #<< and #tell"
    end
    @output_stream = stream
    @entry_set = ::Zip::EntrySet.new
    @state = :before_entry
  end

  # Writes a part of a zip entry body (actual binary data of the entry) into the output stream.
  #
  # @param binary_data [String] a String in binary encoding
  # @return [Streamer] self
  def <<(binary_data)
    transition_or_maintain! :in_entry_body
    @output_stream << binary_data
    @bytes_written_for_entry += binary_data.bytesize
    self
  end
  
  # Writes out the local header for an entry (file in the ZIP) that is using the deflated storage model (is compressed).
  # Once this method is called, the `<<` method has to be called to write the actual contents of the body.
  #
  # Note that the deflated body that is going to be written into the output has to be _precompressed_ (pre-deflated)
  # before writing it into the Streamer, because otherwise it is impossible to know it's size upfront.
  #
  # @param entry_name [String] the name of the file in the entry
  # @param uncompressed_size [Fixnum] the size of the entry when uncompressed, in bytes
  # @param crc32 [Fixnum] the CRC32 checksum of the entry when uncompressed
  # @param compressed_size [Fixnum] the size of the compressed entry that is going to be written into the archive
  # @return [Fixnum] the offset the output IO is at after writing the entry header
  def add_compressed_entry(entry_name, uncompressed_size, crc32, compressed_size)
    transition! :in_entry_header
    
    entry = ::Zip::Entry.new(@file_name, entry_name)
    entry.compression_method = Zip::Entry::DEFLATED
    entry.crc = crc32
    entry.size = uncompressed_size
    entry.compressed_size = compressed_size
    set_gp_flags_for_filename(entry, entry_name)
    
    @entry_set << entry
    entry.write_local_entry(@output_stream)
    @expected_bytes_for_entry = compressed_size
    @bytes_written_for_entry = 0
    @output_stream.tell
  end
  
  # Writes out the local header for an entry (file in the ZIP) that is using the stored storage model (is stored as-is).
  # Once this method is called, the `<<` method has to be called one or more times to write the actual contents of the body.
  #
  # @param entry_name [String] the name of the file in the entry
  # @param uncompressed_size [Fixnum] the size of the entry when uncompressed, in bytes
  # @param crc32 [Fixnum] the CRC32 checksum of the entry when uncompressed
  # @return [Fixnum] the offset the output IO is at after writing the entry header
  def add_stored_entry(entry_name, uncompressed_size, crc32)
    transition! :in_entry_header

    entry = ::Zip::Entry.new(@file_name, entry_name)
    entry.compression_method = Zip::Entry::STORED
    entry.crc = crc32
    entry.size = uncompressed_size
    entry.compressed_size = uncompressed_size
    set_gp_flags_for_filename(entry, entry_name)
    @entry_set << entry
    entry.write_local_entry(@output_stream)
    @bytes_written_for_entry = 0
    @expected_bytes_for_entry = uncompressed_size
    @output_stream.tell
  end
  
  
  # Writes out the global footer and the directory entry header and the global directory of the ZIP
  # archive using the information about the entries added using `add_stored_entry` and `add_compressed_entry`.
  #
  # Once this method is called, the `Streamer` should be discarded (the ZIP archive is complete).
  #
  # @return [Fixnum] the offset the output IO is at after writing the central directory
  def write_central_directory!
    transition! :in_central_directory
    cdir = Zip::CentralDirectory.new(@entry_set, comment = nil)
    cdir.write_to_stream(@output_stream)
    @output_stream.tell
  end
  
  # Closes the archive. Writes the central directory if it has not yet been written.
  # Switches the Streamer into a state where it can no longer be written to.
  #
  # Once this method is called, the `Streamer` should be discarded (the ZIP archive is complete).
  #
  # @return [Fixnum] the offset the output IO is at after closing the archive
  def close
    write_central_directory! unless in_state?(:in_central_directory)
    transition! :closed
    @output_stream.tell
  end
    
  private
  
  # Set the general purpose flags for the entry. The only flag we care about is the EFS
  # bit (bit 11) which should be set if the filename is UTF8. If it is, we need to set the
  # bit so that the unarchiving application knows that the filename in the archive is UTF-8
  # encoded, and not some DOS default. For ASCII entries it does not matter.
  def set_gp_flags_for_filename(entry, filename)
    filename.encode(Encoding::ASCII)
    entry.gp_flags = DEFAULT_GP_FLAGS
  rescue Encoding::UndefinedConversionError #=> UTF8 filename
    entry.gp_flags = DEFAULT_GP_FLAGS | EFS
  end
  
  # Checks whether the number of bytes written conforms to the declared entry size
  def leaving_in_entry_body_state
    if @bytes_written_for_entry != @expected_bytes_for_entry
      msg = "Wrong number of bytes written for entry (expected %d, got %d)" % [@expected_bytes_for_entry, @bytes_written_for_entry]
      raise EntryBodySizeMismatch, msg
    end
  end
  
  def in_state?(state)
    @state == state
  end
  
  def transition_or_maintain!(new_state)
    @recorded_transitions ||= []
    return if @state == new_state
    transition!(new_state)
  end
  
  def expect!(state)
    raise InvalidFlow, "Must be in #{state} state, but was in #{@state}" unless @state == state
  end

  def transition!(new_state)
    raise "Unknown state #{new_state}" unless STATES.include?(new_state)
    if TRANSITIONS.include?([@state, new_state])
      send("leaving_#{@state}_state") if respond_to?("leaving_#{@state}_state", also_protected_and_private=true)
      @state = new_state
    else
      raise InvalidFlow, "Cannot change states from #{@state} to #{new_state} (flow so far: #{@recorded_transitions.join('>')})"
    end
  end
end