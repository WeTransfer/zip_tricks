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
  STATES = [:before_entry, :in_entry_header, :in_entry_body, :in_central_directory, :closed]
  TRANSITIONS = [
    [:before_entry, :in_entry_header],
    [:in_entry_header, :in_entry_body],
    [:in_entry_body, :in_entry_header],
    [:in_entry_body, :in_central_directory],
    [:in_central_directory, :closed]
  ]
  
  # Creates a new Streamer on top of the given IO-ish object and yields it. Once the given block
  # returns, the Streamer will have it's `close` method called, which will write out the central
  # directory of the archive to the output.
  #
  # @param stream [IO] the destination IO for the ZIP (should respond to `tell` and `<<`)
  # @yield archive [Streamer] the streamer that can be written to
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
  # @return self
  def <<(binary_data)
    transition_or_maintain! :in_entry_body
    @output_stream << binary_data
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
  # @return self
  def add_compressed_entry(entry_name, uncompressed_size, crc32, compressed_size)
    transition! :in_entry_header
    
    entry = ::Zip::Entry.new(@file_name, entry_name)
    entry.compression_method = Zip::Entry::DEFLATED
    entry.crc = crc32
    entry.size = uncompressed_size
    entry.compressed_size = compressed_size
    entry.gp_flags = "0000000".to_i(2)
    
    entry.write_local_entry(@output_stream)
    @entry_set << entry
    self
  end
  
  # Writes out the local header for an entry (file in the ZIP) that is using the stored storage model (is stored as-is).
  # Once this method is called, the `<<` method has to be called one or more times to write the actual contents of the body.
  #
  # @param entry_name [String] the name of the file in the entry
  # @param uncompressed_size [Fixnum] the size of the entry when uncompressed, in bytes
  # @param crc32 [Fixnum] the CRC32 checksum of the entry when uncompressed
  # @return self
  def add_stored_entry(entry_name, uncompressed_size, crc32)
    transition! :in_entry_header

    entry = ::Zip::Entry.new(@file_name, entry_name)
    entry.compression_method = Zip::Entry::STORED
    entry.crc = crc32
    entry.size = uncompressed_size
    entry.compressed_size = uncompressed_size
    entry.gp_flags = "0000000".to_i(2)
    @entry_set << entry
    entry.write_local_entry(@output_stream)
  end
  
  # Writes out the global footer and the directory entry header and the global directory of the ZIP
  # archive using the information about the entries added using `add_stored_entry` and `add_compressed_entry`.
  #
  # Once this method is called, the `Streamer` should be discarded (the ZIP archive is complete).
  #
  # @return self
  def close
    transition! :in_central_directory
    cdir = Zip::CentralDirectory.new(@entry_set, comment = nil)
    cdir.write_to_stream(@output_stream)
    transition! :closed
    self
  end
  
  private
  
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
      @state = new_state
    else
      raise InvalidFlow, "Cannot change states from #{@state} to #{new_state} (flow: #{@recorded_transitions.inspect})"
    end
  end
end