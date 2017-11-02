# frozen_string_literal: true

# Rubocop: convention: Missing top-level class documentation comment.
class ZipTricks::Streamer::StoredWriter
  def initialize(io)
    @io = io
    @uncompressed_size = 0
    @compressed_size = 0
    @started_at = @io.tell
    @crc = ZipTricks::WriteBuffer.new(ZipTricks::StreamCRC32.new, 64 * 1024)
  end

  def <<(data)
    @io << data
    @crc << data
    self
  end

  def finish
    size = @io.tell - @started_at
    {crc32: @crc.to_i, compressed_size: size, uncompressed_size: size}
  end
end
