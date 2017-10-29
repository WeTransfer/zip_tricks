# frozen_string_literal: true

class ZipTricks::Streamer::DeflatedWriter
  # After how many bytes of incoming data the deflater for the
  # contents must be flushed. This is done to prevent unreasonable
  # memory use when archiving large files.
  FLUSH_EVERY_N_BYTES = 1024 * 1024 * 5

  def initialize(io)
    @io = io
    @uncompressed_size = 0
    @started_at = @io.tell
    @crc = ZipTricks::StreamCRC32.new
    @deflater = ::Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -::Zlib::MAX_WBITS)
    @bytes_since_last_flush = 0
  end

  def finish
    @io << @deflater.finish until @deflater.finished?
    {crc32: @crc.to_i, compressed_size: @io.tell - @started_at, uncompressed_size: @uncompressed_size}
  end

  def <<(data)
    @uncompressed_size += data.bytesize
    @bytes_since_last_flush += data.bytesize
    @io << @deflater.deflate(data)
    @crc << data
    interim_flush
    self
  end

  private

  def interim_flush
    return if @bytes_since_last_flush < FLUSH_EVERY_N_BYTES
    @io << @deflater.flush
    @bytes_since_last_flush = 0
  end
end
