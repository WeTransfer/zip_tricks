# frozen_string_literal: true

# Sends writes to the given `io`, and also registers all the data passing
# through it in a CRC32 checksum calculator. Is made to be completely
# interchangeable with the DeflatedWriter in terms of interface.
class ZipTricks::Streamer::StoredWriter
  # The amount of bytes we will buffer before computing the intermediate
  # CRC32 checksums. Benchmarks show that the optimum is 64KB (see
  # `bench/buffered_crc32_bench.rb), if that is exceeded Zlib is going
  # to perform internal CRC combine calls which will make the speed go down again.
  CRC32_BUFFER_SIZE = 64 * 1024

  def initialize(io)
    @io = ZipTricks::WriteAndTell.new(io)
    @crc_compute = ZipTricks::StreamCRC32.new
    @crc = ZipTricks::WriteBuffer.new(@crc_compute, CRC32_BUFFER_SIZE)
  end

  # Writes the given data to the contained IO object.
  #
  # @param data[String] data to be written
  # @return self
  def <<(data)
    @io << data
    @crc << data
    self
  end

  # Returns the amount of data written and the CRC32 checksum. The return value
  # can be directly used as the argument to {Streamer#update_last_entry_and_write_data_descriptor}
  #
  # @return [Hash] a hash of `{crc32, compressed_size, uncompressed_size}`
  def finish
    @crc.flush
    {crc32: @crc_compute.to_i, compressed_size: @io.tell, uncompressed_size: @io.tell}
  end
end
