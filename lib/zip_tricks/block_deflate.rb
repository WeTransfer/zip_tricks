# Permits Deflate compression in independent blocks. The workflow is as follows:
#
# * Run every block to compress through compress_block(), memorize the adler32 value and the size of the compressed block
# * Write out the deflate header (\120\156)
# * Write out the compressed block bodies (the ones compress_block has written to your output, in sequence)
# * Combine the adler32 values of all the blocks
# * Write out the footer (\03\00)
# * Write out the combined adler32 value packed in big-endian 32-bit.
module ZipTricks::BlockDeflate
  DEFAULT_BLOCKSIZE = 1024*1024*5
  END_MARKER = [3, 0].pack("C*")
  
  # Compress a given binary string and flush the deflate stream at byte boundary.
  # The returned string can be spliced into another deflate stream.
  #
  # @param bytes [String] Bytes to compress
  # @return [String] compressed bytes
  def self.deflate_chunk(bytes)
    z = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION)#, -::Zlib::MAX_WBITS)
    compressed_blob = z.deflate(bytes, Zlib::SYNC_FLUSH)
    compressed_blob << z.finish
    z.close
    
    # Remove the header (2 bytes), the [3,0] end marker and the adler (4 bytes)
    body_without_header_and_footer = compressed_blob[2..-7]
    block_adler = compressed_blob[-5..-1]
    body_without_header_and_footer
  end
  
  # Compress the contents of input_io into output_io, in blocks
  # of block_size. Align the parts so that they can be concatenated later.
  # Terminate the output to output_io with the end marker (\x3\x0).
  #
  # Compress a given binary string and flush the deflate stream at byte boundary.
  # The returned string can be spliced into another deflate stream.
  #
  # @param input_io [IO] the stream to read from (should respond to `:read`)
  # @param output_io [IO] the stream to write to (should respond to `:<<`)
  # @param block_size [Fixnum] The block size to use (defaults to `DEFAULT_BLOCKSIZE`)
  # @return [Fixnum] number of bytes written to `output_io`
  def self.deflate_in_blocks(input_io, output_io, block_size = DEFAULT_BLOCKSIZE)
    written = 0
    while block = input_io.read(block_size)
      deflated = deflate_chunk(block)
      output_io << deflated
      written += deflated.bytesize
    end
    output_io << END_MARKER
    written + 2
  end
end