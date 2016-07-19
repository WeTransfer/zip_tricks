class ZipTricks::CompressingStreamer
  class StoredWriter
    attr_reader :compressed_size, :uncompressed_size
    def initialize(io)
      @io = io
      @uncompressed_size = 0
      @compressed_size = 0
      @started_at = io.tell
      @crc = ZipTricks::StreamCRC32.new
    end
    
    def crc32
      @crc.to_i
    end
    
    def <<(data)
      @uncompressed_size += data.bytesize
      @io << data
      @crc << data
      self
    end
    
    def write(data)
      self << data
      data.bytesize
    end
    
    def finish
      @compressed_size = @uncompressed_size
    end
  end
  
  class DeflatedWriter
    attr_reader :compressed_size, :uncompressed_size
    def initialize(io)
      @io = io
      @uncompressed_size = 0
      @compressed_size = 0
      @started_at = @io.tell
      @crc = ZipTricks::StreamCRC32.new
    end
    
    def crc32
      @crc.to_i
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
      @compressed_size = @io.tell - @started_at
    end
  end
  
  def initialize(out)
    @io = out
    @zip = ZipTricks::Microzip.new
  end
  
  def add_file_stored(filename)
    @zip.add_local_file_header_of_unknown_size(io: @io, filename: filename, storage_mode: 0)
    w = StoredWriter.new(@io)
    yield(w)
    w.finish
    @zip.write_data_descriptor(io: @io, crc32: w.crc32, compressed_size: w.compressed_size,
      uncompressed_size: w.uncompressed_size)
  end
  
  def add_file_deflated(filename)
    @zip.add_local_file_header_of_unknown_size(io: @io, filename: filename, storage_mode: 8)
    w = DeflatedWriter.new(@io)
    yield(w)
    w.finish
    @zip.write_data_descriptor(io: @io, crc32: w.crc32, compressed_size: w.compressed_size,
      uncompressed_size: w.uncompressed_size)
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
