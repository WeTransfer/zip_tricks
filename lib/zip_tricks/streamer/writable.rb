# frozen_string_literal: true

# Gets yielded from the writing methods of the Streamer
# and accepts the data being written into the ZIP for deflate
# or stored modes. Can be used as a destination for `IO.copy_stream`
#
#    IO.copy_stream(File.open('source.bin', 'rb), writable)
class ZipTricks::Streamer::Writable
  # Initializes a new Writable with the object it delegates the writes to.
  # Normally you would not need to use this method directly
  def initialize(streamer, writer)
    @streamer = streamer
    @writer = writer
    @closed = false
  end

  # Writes the given data to the output stream
  #
  # @param d[String] the binary string to write (part of the uncompressed file)
  # @return [self]
  def <<(d)
    raise 'Trying to write to a closed Writable' if @closed
    @writer << d
    self
  end

  # Writes the given data to the output stream
  #
  # @param d[String] the binary string to write (part of the uncompressed file)
  # @return [Fixnum] the number of bytes written
  def write(d)
    self << d
    d.bytesize
  end

  # Flushes the writer and recovers the CRC32/size values. It then calls
  # `update_last_entry_and_write_data_descriptor` on the given Streamer.
  def close
    return if @closed
    @streamer.update_last_entry_and_write_data_descriptor(**@writer.finish)
    @closed = true
  end
end
