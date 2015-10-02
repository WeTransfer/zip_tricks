# Permits Deflate compression in independent blocks. The workflow is as follows:
#
# * Run every block to compress through compress_block(), memorize the adler32 value and the size of the compressed block
# * Write out the deflate header (\120\156)
# * Write out the compressed block bodies (the ones compress_block has written to your output, in sequence)
# * Combine the adler32 values of all the blocks
# * Write out the footer (\03\00)
# * Write out the combined adler32 value packed in big-endian 32-bit.
module ZipTricks::BlockDeflate
  BLOCKSIZE = 1024*1024*5
  HEADER = [120, 156].pack("C*")
  END_MARKER = [3, 0].pack("C*")
  MalformedDeflate = Class.new(StandardError)
  
  # Compress the contents of input_io into output_io, in blocks
  # of 5 Mb. Align the parts so that they can be concatenated later.
  # The parts get written without the footer and without the header (because the
  # zip deflate storage omits the header).
  #
  # The computed adler32 checksum for all the blocks gets returned (as a Fixnum), to be combined later during concatenation.
  def self.compress_block(input_io, output_io, compression_level = Zlib::DEFAULT_COMPRESSION)
    running_adler = Zlib.adler32('') # Has to be started with an adler32 value for an empty string!
    until input_io.eof?
      block = input_io.read(BLOCKSIZE)
      
      # We need two parts of the equation. Zlib.deflate() only gives us the body
      z = Zlib::Deflate.new(compression_level)
      header_and_body = z.deflate(block, Zlib::SYNC_FLUSH)
      footer = z.finish
      z.close
      
      discarded_end_mark, block_adler = footer[0..1], footer[2..-1]
      raise MalformedDeflate, 'Footer should be 6 bytes' unless footer.bytesize == 6
      raise MalformedDeflate, 'End marker should be \x03\x00' unless discarded_end_mark == END_MARKER
      raise MalformedDeflate, 'Adler should be 4 bytes' unless block_adler.bytesize == 4
      
      header, body = header_and_body[0..1], header_and_body[2..-1]
      raise MalformedDeflate, 'Header should be \x120\x156' unless header == HEADER
      
      output_io << body
      
      # The Adler32 checksum value is for the inflated (uncompressed) block
      # that was compressed in the first place, and is stored in big-endian.
      # You will get the same value if you do Zlib.adler32(block).
      block_adler = block_adler.unpack("N").first
      # The byte size used to combine the adler checksums also has to be the size
      # of the original block, not of the compressed body!
      running_adler = Zlib.adler32_combine(running_adler, block_adler, block.bytesize)
    end
    running_adler
  end
  
  # Pack the adler32 checksum into a big-endian byte string
  def self.pack_adler_int(adler32_int)
    [adler32_int].pack("N")
  end
end