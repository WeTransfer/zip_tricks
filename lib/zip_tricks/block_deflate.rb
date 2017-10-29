# frozen_string_literal: true

require 'zlib'

# Permits Deflate compression in independent blocks. The workflow is as follows:
#
# * Run every block to compress through deflate_chunk, remove the header,
#   footer and adler32 from the result
# * Write out the compressed block bodies (the ones deflate_chunk returns)
#   to your output, in sequence
# * Write out the footer (\03\00)
#
# The resulting stream is guaranteed to be handled properly by all zip
# unarchiving tools, including the BOMArchiveHelper/ArchiveUtility on OSX.
#
# You could also build a compressor for Rubyzip using this module quite easily,
# even though this is outside the scope of the library.
#
# When you deflate the chunks separately, you need to write the end marker
# yourself (using `write_terminator`).
# If you just want to deflate a large IO's contents, use
# `deflate_in_blocks_and_terminate` to have the end marker written out for you.
#
# Basic usage to compress a file in parts:
#
#     source_file = File.open('12_gigs.bin', 'rb')
#     compressed = Tempfile.new
#     # Will not compress everything in memory, but do it per chunk to spare
#       memory. `compressed`
#     # will be written to at the end of each chunk.
#     ZipTricks::BlockDeflate.deflate_in_blocks_and_terminate(source_file,
#                                                             compressed)
#
# You can also do the same to parts that you will later concatenate together
# elsewhere, in that case you need to skip the end marker:
#
#     compressed = Tempfile.new
#     ZipTricks::BlockDeflate.deflate_in_blocks(File.open('part1.bin', 'rb),
#                                               compressed)
#     ZipTricks::BlockDeflate.deflate_in_blocks(File.open('part2.bin', 'rb),
#                                               compressed)
#     ZipTricks::BlockDeflate.deflate_in_blocks(File.open('partN.bin', 'rb),
#                                               compressed)
#     ZipTricks::BlockDeflate.write_terminator(compressed)
#
# You can also elect to just compress strings in memory (to splice them later):
#
#     compressed_string = ZipTricks::BlockDeflate.deflate_chunk(big_string)

class ZipTricks::BlockDeflate
  DEFAULT_BLOCKSIZE = 1_024 * 1024 * 5
  END_MARKER = [3, 0].pack('C*')
  # Zlib::NO_COMPRESSION..
  VALID_COMPRESSIONS = (Zlib::DEFAULT_COMPRESSION..Zlib::BEST_COMPRESSION).to_a.freeze
  # Write the end marker (\x3\x0) to the given IO.
  #
  # `output_io` can also be a {ZipTricks::Streamer} to expedite ops.
  #
  # @param output_io [IO] the stream to write to (should respond to `:<<`)
  # @return [Fixnum] number of bytes written to `output_io`
  def self.write_terminator(output_io)
    output_io << END_MARKER
    END_MARKER.bytesize
  end

  # Compress a given binary string and flush the deflate stream at byte boundary.
  # The returned string can be spliced into another deflate stream.
  #
  # @param bytes [String] Bytes to compress
  # @param level [Fixnum] Zlib compression level (defaults to `Zlib::DEFAULT_COMPRESSION`)
  # @return [String] compressed bytes
  def self.deflate_chunk(bytes, level: Zlib::DEFAULT_COMPRESSION)
    raise "Invalid Zlib compression level #{level}" unless VALID_COMPRESSIONS.include?(level)
    z = Zlib::Deflate.new(level)
    compressed_blob = z.deflate(bytes, Zlib::SYNC_FLUSH)
    compressed_blob << z.finish
    z.close

    # Remove the header (2 bytes), the [3,0] end marker and the adler (4 bytes)
    compressed_blob[2...-6]
  end

  # Compress the contents of input_io into output_io, in blocks
  # of block_size. Aligns the parts so that they can be concatenated later.
  # Writes deflate end marker (\x3\x0) into `output_io` as the final step, so
  # the contents of `output_io` can be spliced verbatim into a ZIP archive.
  #
  # Once the write completes, no more parts for concatenation should be written to
  # the same stream.
  #
  # `output_io` can also be a {ZipTricks::Streamer} to expedite ops.
  #
  # @param input_io [IO] the stream to read from (should respond to `:read`)
  # @param output_io [IO] the stream to write to (should respond to `:<<`)
  # @param level [Fixnum] Zlib compression level (defaults to `Zlib::DEFAULT_COMPRESSION`)
  # @param block_size [Fixnum] The block size to use (defaults to `DEFAULT_BLOCKSIZE`)
  # @return [Fixnum] number of bytes written to `output_io`
  def self.deflate_in_blocks_and_terminate(input_io,
                                           output_io,
                                           level: Zlib::DEFAULT_COMPRESSION,
                                           block_size: DEFAULT_BLOCKSIZE)
    bytes_written = deflate_in_blocks(input_io, output_io, level: level, block_size: block_size)
    bytes_written + write_terminator(output_io)
  end

  # Compress the contents of input_io into output_io, in blocks
  # of block_size. Align the parts so that they can be concatenated later.
  # Will not write the deflate end marker (\x3\x0) so more parts can be written
  # later and succesfully read back in provided the end marker wll be written.
  #
  # `output_io` can also be a {ZipTricks::Streamer} to expedite ops.
  #
  # @param input_io [IO] the stream to read from (should respond to `:read`)
  # @param output_io [IO] the stream to write to (should respond to `:<<`)
  # @param level [Fixnum] Zlib compression level (defaults to `Zlib::DEFAULT_COMPRESSION`)
  # @param block_size [Fixnum] The block size to use (defaults to `DEFAULT_BLOCKSIZE`)
  # @return [Fixnum] number of bytes written to `output_io`
  def self.deflate_in_blocks(input_io,
                             output_io,
                             level: Zlib::DEFAULT_COMPRESSION,
                             block_size: DEFAULT_BLOCKSIZE)
    bytes_written = 0
    while block = input_io.read(block_size)
      deflated = deflate_chunk(block, level: level)
      output_io << deflated
      bytes_written += deflated.bytesize
    end
    bytes_written
  end
end
