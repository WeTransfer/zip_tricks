class ZipTricks::Streamer::StoredWriter
  def initialize(io)
    @io = io
    @uncompressed_size = 0
    @compressed_size = 0
    @started_at = @io.tell
    @crc = ZipTricks::StreamCRC32.new
  end

  def <<(data)
    @io << data
    @crc << data
    self
  end

  def write(data)
    self << data
    data.bytesize
  end

  def finish
    size = @io.tell - @started_at
    [@crc.to_i, size, size]
  end
end