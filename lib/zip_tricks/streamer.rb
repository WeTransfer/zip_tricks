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
  require_relative 'streamer/deflated_writer'
  require_relative 'streamer/writable'
  require_relative 'streamer/stored_writer'
  require_relative 'streamer/entry'

  EntryBodySizeMismatch = Class.new(StandardError)
  InvalidOutput = Class.new(ArgumentError)

  STORED, DEFLATED = 0, 8

  Overflow = Class.new(StandardError)
  PathError = Class.new(StandardError)
  DuplicateFilenames = Class.new(StandardError)
  UnknownMode = Class.new(StandardError)

  private_constant :DeflatedWriter, :StoredWriter, :STORED, :DEFLATED

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
  # @param stream [IO] the destination IO for the ZIP (should respond to `<<`)
  def initialize(stream)
    raise InvalidOutput, "The stream should respond to #<<" unless stream.respond_to?(:<<)
    stream = ZipTricks::WriteAndTell.new(stream) unless stream.respond_to?(:tell) && stream.respond_to?(:advance_position_by)

    @out = stream
    @files = []
    @local_header_offsets = []
    @writer = ZipTricks::ZipWriter.new

    @state_monitor = VeryTinyStateMachine.new(:before_entry, callbacks_to=self)
    @state_monitor.permit_state :in_entry_header, :in_entry_body, :in_central_directory, :in_data_descriptor, :closed
    @state_monitor.permit_transition :before_entry => :in_entry_header
    @state_monitor.permit_transition :in_entry_header => :in_entry_body
    @state_monitor.permit_transition :in_entry_header => :in_data_descriptor
    @state_monitor.permit_transition :in_entry_body => :in_entry_header
    @state_monitor.permit_transition :in_entry_body => :in_central_directory
    @state_monitor.permit_transition :in_entry_body => :in_data_descriptor
    @state_monitor.permit_transition :in_data_descriptor => :in_entry_header
    @state_monitor.permit_transition :in_data_descriptor => :in_central_directory
    @state_monitor.permit_transition :in_central_directory => :closed
  end

  # Writes a part of a zip entry body (actual binary data of the entry) into the output stream.
  #
  # @param binary_data [String] a String in binary encoding
  # @return self
  def <<(binary_data)
    @state_monitor.transition_or_maintain! :in_entry_body
    @out << binary_data
    @bytes_written_for_entry += binary_data.bytesize
    self
  end

  # Writes a part of a zip entry body (actual binary data of the entry) into the output stream,
  # and returns the number of bytes written. Is implemented to make Streamer usable with
  # `IO.copy_stream(from, to)`.
  #
  # @param binary_data [String] a String in binary encoding
  # @return [Fixnum] the number of bytes written
  def write(binary_data)
    self << binary_data
    binary_data.bytesize
  end

  # Advances the internal IO pointer to keep the offsets of the ZIP file in check. Use this if you are going
  # to use accelerated writes to the socket (like the `sendfile()` call) after writing the headers, or if you
  # just need to figure out the size of the archive.
  #
  # @param num_bytes [Numeric] how many bytes are going to be written bypassing the Streamer
  # @return [Numeric] position in the output stream / ZIP archive
  def simulate_write(num_bytes)
    @state_monitor.transition_or_maintain! :in_entry_body
    @out.advance_position_by(num_bytes)
    @bytes_written_for_entry += num_bytes
    @out.tell
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
    @state_monitor.transition! :in_entry_header
    add_file_and_write_local_header(filename: entry_name, crc32: crc32, storage_mode: DEFLATED, 
      compressed_size: compressed_size, uncompressed_size: uncompressed_size)
    @bytes_written_for_entry = 0
    @expected_bytes_for_entry = compressed_size
    @out.tell
  end

  # Writes out the local header for an entry (file in the ZIP) that is using the stored storage model (is stored as-is).
  # Once this method is called, the `<<` method has to be called one or more times to write the actual contents of the body.
  #
  # @param entry_name [String] the name of the file in the entry
  # @param uncompressed_size [Fixnum] the size of the entry when uncompressed, in bytes
  # @param crc32 [Fixnum] the CRC32 checksum of the entry when uncompressed
  # @return [Fixnum] the offset the output IO is at after writing the entry header
  def add_stored_entry(entry_name, uncompressed_size, crc32)
    @state_monitor.transition! :in_entry_header
    add_file_and_write_local_header(filename: entry_name, crc32: crc32, storage_mode: STORED,
      compressed_size: uncompressed_size, uncompressed_size: uncompressed_size)
    @bytes_written_for_entry = 0
    @expected_bytes_for_entry = uncompressed_size
    @out.tell
  end

  # Writes out the global footer and the directory entry header and the global directory of the ZIP
  # archive using the information about the entries added using `add_stored_entry` and `add_compressed_entry`.
  #
  # Once this method is called, the `Streamer` should be discarded (the ZIP archive is complete).
  #
  # @return [Fixnum] the offset the output IO is at after writing the central directory
  def write_central_directory!
    @state_monitor.transition! :in_central_directory

    # Write out the central directory file headers, one by one
    cdir_starts_at = @out.tell
    @files.each_with_index do |entry, i|
      header_loc = @local_header_offsets.fetch(i)

      @writer.write_central_directory_file_header(io: @out, local_file_header_location: header_loc,
        gp_flags: entry.gp_flags, storage_mode: entry.storage_mode, compressed_size: entry.compressed_size, uncompressed_size: entry.uncompressed_size,
        mtime: entry.mtime, crc32: entry.crc32, filename: entry.filename) #, external_attrs: DEFAULT_EXTERNAL_ATTRS)
    end
    cdir_size = @out.tell - cdir_starts_at

    # Write out the EOCDR
    @writer. write_end_of_central_directory(io: @out, start_of_central_directory_location: cdir_starts_at,
       central_directory_size: cdir_size, num_files_in_archive: @files.length)

    @out.tell
  end

  # Opens the stream for a stored file in the archive, and yields a writer for that file to the block.
  # Once the write completes, a data descriptor will be written with the actual compressed/uncompressed
  # sizes and the CRC32 checksum.
  #
  # @param filename[String] the name of the file in the archive
  # @yield [#<<, #write] an object that the file contents must be written to
  def write_stored_file(filename)
    @state_monitor.transition! :in_entry_header
    add_file_and_write_local_header(filename: filename, storage_mode: STORED,
      use_data_descriptor: true, crc32: 0, compressed_size: 0, uncompressed_size: 0)

    @state_monitor.transition! :in_entry_body
    
    w = StoredWriter.new(@out)
    yield(Writable.new(w))
    crc, comp, uncomp = w.finish

    # Save the information into the entry for when the time comes to write out the central directory
    last_entry = @files[-1]
    last_entry.crc32 = crc
    last_entry.compressed_size = comp
    last_entry.uncompressed_size = uncomp

    @state_monitor.transition! :in_data_descriptor
    @writer.write_data_descriptor(io: @out, crc32: crc, compressed_size: comp, uncompressed_size: uncomp)
  end

  # Opens the stream for a deflated file in the archive, and yields a writer for that file to the block.
  # Once the write completes, a data descriptor will be written with the actual compressed/uncompressed
  # sizes and the CRC32 checksum.
  #
  # @param filename[String] the name of the file in the archive
  # @yield [#<<, #write] an object that the file contents must be written to
  def write_deflated_file(filename)
    @state_monitor.transition! :in_entry_header
    add_file_and_write_local_header(filename: filename, storage_mode: DEFLATED,
      use_data_descriptor: true, crc32: 0, compressed_size: 0, uncompressed_size: 0)

    @state_monitor.transition! :in_entry_body
    
    w = DeflatedWriter.new(@out)
    yield(Writable.new(w))
    crc, comp, uncomp = w.finish

    # Save the information into the entry for when the time comes to write out the central directory
    last_entry = @files[-1]
    last_entry.crc32 = crc
    last_entry.compressed_size = comp
    last_entry.uncompressed_size = uncomp

    @state_monitor.transition! :in_data_descriptor
    @writer.write_data_descriptor(io: @out, crc32: crc, compressed_size: comp, uncompressed_size: uncomp)
  end

  # Closes the archive. Writes the central directory if it has not yet been written.
  # Switches the Streamer into a state where it can no longer be written to.
  #
  # Once this method is called, the `Streamer` should be discarded (the ZIP archive is complete).
  #
  # @return [Fixnum] the offset the output IO is at after closing the archive
  def close
    write_central_directory! unless @state_monitor.in_state?(:in_central_directory)
    @state_monitor.transition! :closed
    @out.tell
  end

  private

  def add_file_and_write_local_header(filename:, crc32:, storage_mode:, compressed_size:, uncompressed_size:, use_data_descriptor: false)
    if @files.any?{|e| e.filename == filename }
      raise DuplicateFilenames, "Filename #{filename.inspect} already used in the archive"
    end
    
    raise UnknownMode, "Unknown compression mode #{storage_mode}" unless [STORED, DEFLATED].include?(storage_mode)
    
    raise Overflow, "Filename is too long" if filename.bytesize > 0xFFFF
    raise PathError, "Paths in ZIP may only contain forward slashes (UNIX separators)" if filename.include?('\\')
    
    e = Entry.new(filename, crc32, compressed_size, uncompressed_size, storage_mode, mtime=Time.now.utc, use_data_descriptor)
    @files << e
    @local_header_offsets << @out.tell
    @writer.write_local_file_header(io: @out, gp_flags: e.gp_flags, crc32: e.crc32, compressed_size: e.compressed_size,
      uncompressed_size: e.uncompressed_size, mtime: e.mtime, filename: e.filename, storage_mode: e.storage_mode)
  end
  
  # Checks whether the number of bytes written conforms to the declared entry size
  def leaving_in_entry_body_state
    if @bytes_written_for_entry != @expected_bytes_for_entry
      msg = "Wrong number of bytes written for entry (expected %d, got %d)" % [@expected_bytes_for_entry, @bytes_written_for_entry]
      raise EntryBodySizeMismatch, msg
    end
  end
end
