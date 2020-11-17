# frozen_string_literal: true

# Sends writes to the given `io` compressed using a {Zlib::Deflate}. Also
# registers data passing through it in a CRC32 checksum calculator. Is made to be completely
# interchangeable with the StoredWriter in terms of interface.
class ZipTricks::Streamer::DeflatedWriter
  # The amount of bytes we will buffer before computing the intermediate
  # CRC32 checksums. Benchmarks show that the optimum is 64KB (see
  # `bench/buffered_crc32_bench.rb), if that is exceeded Zlib is going
  # to perform internal CRC combine calls which will make the speed go down again.
  CRC32_BUFFER_SIZE = 64 * 1024

  def initialize(io)
    @compressed_io = io
    @deflater = ::Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -::Zlib::MAX_WBITS)
    @crc = ZipTricks::WriteBuffer.new(ZipTricks::StreamCRC32.new, CRC32_BUFFER_SIZE)
  end

  # Writes the given data into the deflater, and flushes the deflater
  # after having written more than FLUSH_EVERY_N_BYTES bytes of data
  #
  # @param data[String] data to be written
  # @return self
  def <<(data)
    @compressed_io << @deflater.deflate(data)
    @crc << data
    self
  end

  # Returns the amount of data received for writing, the amount of
  # compressed data written and the CRC32 checksum. The return value
  # can be directly used as the argument to {Streamer#update_last_entry_and_write_data_descriptor}
  #
  # @return [Hash] a hash of `{crc32, compressed_size, uncompressed_size}`
  def finish
    @compressed_io << @deflater.finish until @deflater.finished?
    {crc32: @crc.to_i, compressed_size: @deflater.total_out, uncompressed_size: @deflater.total_in}
  end
end
