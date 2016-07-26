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
  
  EntryBodySizeMismatch = Class.new(StandardError)
  InvalidOutput = Class.new(ArgumentError)

  private_constant :DeflatedWriter, :StoredWriter

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
    raise InvalidOutput, "The stream should respond to #<<" unless stream.respond_to?(:<<)
    stream = ZipTricks::WriteAndTell.new(stream) unless stream.respond_to?(:tell) && stream.respond_to?(:advance_position_by)
    
    @output_stream = stream
    @zip = ZipTricks::Microzip.new
    
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
    @output_stream << binary_data
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
    @output_stream.advance_position_by(num_bytes)
    @bytes_written_for_entry += num_bytes
    @output_stream.tell
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
    @zip.add_local_file_header(io: @output_stream, filename: entry_name, crc32: crc32,
      compressed_size: compressed_size, uncompressed_size: uncompressed_size, storage_mode: ZipTricks::Microzip::DEFLATED)
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
    @state_monitor.transition! :in_entry_header
    @zip.add_local_file_header(io: @output_stream, filename: entry_name, crc32: crc32,
      compressed_size: uncompressed_size, uncompressed_size: uncompressed_size, storage_mode: ZipTricks::Microzip::STORED)
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
    @state_monitor.transition! :in_central_directory
    @zip.write_central_directory(@output_stream)
    @output_stream.tell
  end

  # Opens the stream for a stored file in the archive, and yields a writer for that file to the block.
  # Once the write completes, a data descriptor will be written with the actual compressed/uncompressed
  # sizes and the CRC32 checksum.
  #
  # @param filename[String] the name of the file in the archive
  # @yieldd [#<<, #write] an object that the file contents must be written to
  def write_stored_file(filename)
    @state_monitor.transition! :in_entry_header
    @zip.add_local_file_header_of_unknown_size(io: @output_stream, filename: filename, storage_mode: 0)
    @state_monitor.transition! :in_entry_body
    w = StoredWriter.new(@output_stream)
    yield(Writable.new(w))
    crc, comp, uncomp = w.finish
    @state_monitor.transition! :in_data_descriptor
    @zip.write_data_descriptor(io: @output_stream, crc32: crc, compressed_size: comp, uncompressed_size: uncomp)
  end

  # Opens the stream for a deflated file in the archive, and yields a writer for that file to the block.
  # Once the write completes, a data descriptor will be written with the actual compressed/uncompressed
  # sizes and the CRC32 checksum.
  #
  # @param filename[String] the name of the file in the archive
  # @param flush_deflate_after_bytes[Fixnum] how many bytes may be written before the deflater should flush.
  #       The default value for this method should be sufficient for most uses.
  # @yield [#<<, #write] an object that the file contents must be written to
  def write_deflated_file(filename)
    @state_monitor.transition! :in_entry_header
    @zip.add_local_file_header_of_unknown_size(io: @output_stream, filename: filename, storage_mode: 8)
    @state_monitor.transition! :in_entry_body
    w = DeflatedWriter.new(@output_stream)
    yield(Writable.new(w))
    crc, comp, uncomp = w.finish
    @state_monitor.transition! :in_data_descriptor
    @zip.write_data_descriptor(io: @output_stream, crc32: crc, compressed_size: comp, uncompressed_size: uncomp)
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
    @output_stream.tell
  end

  private

  # Checks whether the number of bytes written conforms to the declared entry size
  def leaving_in_entry_body_state
    if @bytes_written_for_entry != @expected_bytes_for_entry
      msg = "Wrong number of bytes written for entry (expected %d, got %d)" % [@expected_bytes_for_entry, @bytes_written_for_entry]
      raise EntryBodySizeMismatch, msg
    end
  end
end
