class ZipTricks::CompressingStreamer
  # After how many bytes of incoming data the deflater for the
  # contents must be flushed. This is done to prevent unreasonable
  # memory use when archiving large files.
  FLUSH_EVERY_N_BYTES = 1024 * 1024 * 5
  
  # Gets yielded from the writing methods of the CompressingStreamer
  # and accepts the data being written into the ZIP
  class Writable
    # Initializes a new Writable with the object it delegates the writes to.
    # Normally you would not need to use this method directly 
    def initialize(writer)
      @writer = writer
    end
    # Writes the given data to the output stream
    #
    # @param d[String] the binary string to write (part of the uncompressed file)
    # @return [self]
    def <<(d); @writer << d; self; end
    
    # Writes the given data to the output stream
    #
    # @param d[String] the binary string to write (part of the uncompressed file)
    # @return [Fixnum] the number of bytes written
    def write(d); @writer << d; end
  end
  
  class StoredWriter
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

  class DeflatedWriter
    def initialize(io, flush_after_n)
      @flush_after = flush_after_n
      @io = io
      @uncompressed_size = 0
      @started_at = @io.tell
      @crc = ZipTricks::StreamCRC32.new
      @deflater = ::Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -::Zlib::MAX_WBITS)
      @bytes_since_last_flush = 0
    end

    def finish
      @io << @deflater.finish until @deflater.finished?
      [@crc.to_i, @io.tell - @started_at, @uncompressed_size]
    end
    
    def <<(data)
      @uncompressed_size += data.bytesize
      @bytes_since_last_flush += data.bytesize
      @io << @deflater.deflate(data)
      @crc << data
      interim_flush
      self
    end

    def write(data)
      self << data
      data.bytesize
    end
    
    private

    def interim_flush
      return if @bytes_since_last_flush < @flush_after
      @io << @deflater.flush
      @bytes_since_last_flush = 0
    end
  end

  private_constant :StoredWriter, :DeflatedWriter
  
  # Creates a new CompressingStreamer that will write into the given output
  #
  # @param out[#<<, #tell] an object that responds to << and tell (for example, an IO object)
  def initialize(out)
    @io = out
    @zip = ZipTricks::Microzip.new
  end

  # Opens the stream for a stored file in the archive, and yields a writer for that file to the block.
  #
  # @param filename[String] the name of the file in the archive
  # @yieldd [#<<, #write] an object that the file contents must be written to
  def write_stored_file(filename)
    @zip.add_local_file_header_of_unknown_size(io: @io, filename: filename, storage_mode: 0)
    w = StoredWriter.new(@io)
    yield(Writable.new(w))
    crc, comp, uncomp = w.finish
    @zip.write_data_descriptor(io: @io, crc32: crc, compressed_size: comp, uncompressed_size: uncomp)
  end

  # Opens the stream for a deflated file in the archive, and yields a writer for that file to the block.
  #
  # @param filename[String] the name of the file in the archive
  # @param flush_deflate_after_bytes[Fixnum] how many bytes may be written before the deflater should flush.
  #       The default value for this method should be sufficient for most uses.
  # @yield [#<<, #write] an object that the file contents must be written to
  def write_deflated_file(filename, flush_deflate_after_bytes: FLUSH_EVERY_N_BYTES)
    @zip.add_local_file_header_of_unknown_size(io: @io, filename: filename, storage_mode: 8)
    w = DeflatedWriter.new(@io, flush_deflate_after_bytes)
    yield(Writable.new(w))
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
