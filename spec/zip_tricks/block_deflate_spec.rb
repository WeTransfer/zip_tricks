# frozen_string_literal: true

require_relative '../spec_helper'

describe ZipTricks::BlockDeflate do
  def tag_deflated(deflated_string, raw_string)
    [120, 156].pack('C*') + deflated_string + [3, 0].pack('C*') + [Zlib.adler32(raw_string)].pack('N')
  end

  describe '.deflate_chunk' do
    it 'compresses a blob that can be inflated later, when the header, \
        footer and adler32 are added' do
      blob = 'compressible' * 2
      compressed = described_class.deflate_chunk(blob)
      expect(compressed.bytesize).to be < blob.bytesize
      complete_deflated_segment = tag_deflated(compressed, blob)
      expect(Zlib::Inflate.inflate(complete_deflated_segment)).to eq(blob)
    end

    it 'removes the header' do
      blob = 'compressible'
      compressed = described_class.deflate_chunk(blob)
      expect(compressed[0..1]).not_to eq([120, 156].pack('C*'))
    end

    it 'removes the adler32' do
      blob = 'compressible'
      compressed = described_class.deflate_chunk(blob)
      adler = [Zlib.adler32(blob)].pack('N')
      expect(compressed).not_to end_with(adler)
    end

    it 'removes the end marker' do
      blob = 'compressible'
      compressed = described_class.deflate_chunk(blob)
      expect(compressed[-7..-5]).not_to eq([3, 0].pack('C*'))
    end

    it 'honors the compression level' do
      deflater = Zlib::Deflate.new
      expect(Zlib::Deflate).to receive(:new).with(2, any_args) { deflater }
      blob = 'compressible'
      described_class.deflate_chunk(blob, level: 2)
    end
  end

  describe 'deflate_in_blocks_and_terminate' do
    it 'uses deflate_in_blocks' do
      input = TestIO.new('compressible', 1024 * 1024 * 1)
      output = StringIO.new
      block_size = 1024 * 64
      expect(described_class).to receive(:deflate_in_blocks).with(input,
                                                                  output,
                                                                  level: -1,
                                                                  block_size: block_size).and_call_original
      described_class.deflate_in_blocks_and_terminate(input, output, block_size: block_size)
    end

    it 'passes a custom compression level' do
      input = TestIO.new('compressible', 1024 * 1024 * 1)
      output = StringIO.new
      expect(described_class).to receive(:deflate_in_blocks).with(input,
                                                                  output,
                                                                  level: 9,
                                                                  block_size: anything).and_call_original
      described_class.deflate_in_blocks_and_terminate(input, output, level: Zlib::BEST_COMPRESSION)
    end

    it 'writes the end marker' do
      input = TestIO.new('compressible', 1024 * 1024 * 1)
      output = StringIO.new
      described_class.deflate_in_blocks_and_terminate(input, output)
      output.seek(-2, IO::SEEK_END)
      expect(output.read(2)).to eq([3, 0].pack('C*'))
    end
  end

  describe '.write_terminator' do
    it 'writes the terminator and returns 2 for number of bytes written' do
      buf = double('IO')
      expect(buf).to receive(:<<).with([3, 0].pack('C*'))
      expect(described_class.write_terminator(buf)).to eq(2)
    end
  end

  describe '.deflate_in_blocks' do
    it 'honors the block size' do
      input = TestIO.new('compressible', 12 * 1024 * 1024)
      output = NullIO.new
      # output = StringIO.new
      block_size = 1024 * 192

      num_chunks = (input.size + block_size - 1) / block_size
      # expect(described_class).to receive(:deflate_chunk).exactly(num_chunks).times.and_call_original
      expect(input).to receive(:read).with(block_size, any_args).exactly(num_chunks + 1).times.and_call_original
      expect(output).to receive(:<<).exactly(num_chunks + 1).times.and_call_original

      described_class.deflate_in_blocks(input, output, block_size: block_size)
    end

    it 'does not write the end marker' do
      input = TestIO.new('compressible', 1024 * 1024 * 10)
      output = StringIO.new

      described_class.deflate_in_blocks(input, output)
      expect(output.string).not_to be_empty
      expect(output.string).not_to end_with([3, 0].pack('C*'))
    end

    it 'returns the number of bytes written' do
      input = TestIO.new('compressible', 12 * 1024 * 1024)
      output = NullIO.new

      num_bytes = described_class.deflate_in_blocks(input, output)
      expect(num_bytes).to eq(output.size)
      expect(num_bytes).to eq(24_434)
    end
  end
end
