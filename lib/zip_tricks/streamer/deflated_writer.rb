class ZipTricks::Streamer::DeflatedWriter
  def initialize(io)
    @io = io
    @uncompressed_size = 0
    @started_at = @io.tell
    @crc = ZipTricks::StreamCRC32.new
    @bytes_since_last_flush = 0
  end

  def finish
    ZipTricks::BlockDeflate.write_terminator(@io)
    [@crc.to_i, @io.tell - @started_at, @uncompressed_size]
  end
  
  def <<(data)
    @uncompressed_size += data.bytesize
    @io << ZipTricks::BlockDeflate.deflate_chunk(data)
    @crc << data
    self
  end

  def write(data)
    self << data
    data.bytesize
  end
end
