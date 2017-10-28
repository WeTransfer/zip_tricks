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
  end

  # Writes the given data to the output stream
  #
  # @param d[String] the binary string to write (part of the uncompressed file)
  # @return [self]
  def <<(d)
    @writer << d
    self
  end

  # Writes the given data to the output stream
  #
  # @param d[String] the binary string to write (part of the uncompressed file)
  # @return [Fixnum] the number of bytes written
  def write(d)
    @writer << d
    d.bytesize
  end
  
  # Flushes the writer and recovers the CRC32/size values. It then calls
  # `update_last_entry_and_write_data_descriptor` on the given Streamer.
  def close
    @streamer.update_last_entry_and_write_data_descriptor(**@writer.finish)
  end
end
