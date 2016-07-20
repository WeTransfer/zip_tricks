class ZipTricks::CompressingStreamer
  class StoredWriter
    def initialize(io)
      @io = io
      @uncompressed_size = 0
      @compressed_size = 0
      @started_at = io.tell
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

  class DeflatedWriter
    def initialize(io)
      @io = io
      @uncompressed_size = 0
      @started_at = @io.tell
      @crc = ZipTricks::StreamCRC32.new
      self << '' # Start the deflate stream correctly
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

    def finish
      ZipTricks::BlockDeflate.write_terminator(@io)
      [@crc.to_i, @io.tell - @started_at, @uncompressed_size]
    end
  end

  def initialize(out)
    @io = out
    @zip = ZipTricks::Microzip.new
  end

  def write_stored_file(filename)
    @zip.add_local_file_header_of_unknown_size(io: @io, filename: filename, storage_mode: 0)
    w = StoredWriter.new(@io)
    yield(w)
    w.finish
    crc, comp, uncomp = w.finish
    @zip.write_data_descriptor(io: @io, crc32: crc, compressed_size: comp, uncompressed_size: uncomp)
  end

  def write_deflated_file(filename)
    @zip.add_local_file_header_of_unknown_size(io: @io, filename: filename, storage_mode: 8)
    w = DeflatedWriter.new(@io)
    yield(w)
    crc, comp, uncomp = w.finish
    @zip.write_data_descriptor(io: @io, crc32: crc, compressed_size: comp, uncompressed_size: uncomp)
  end

  def close
    @zip.write_central_directory(@io)
  end

  def self.open(io)
    me = new(io)
    yield(me)
    me.close
  end
end
