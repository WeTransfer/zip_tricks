require_relative '../spec_helper'

describe ZipTricks::BlockDeflate do
  def tag_deflated(deflated_string, raw_string)
    [120, 156].pack('C*') + deflated_string + [3, 0].pack('C*') + [Zlib.adler32(raw_string)].pack('N')
  end

  describe '.deflate_chunk' do
    it 'compresses a blob that can be inflated later, when the header, \
        footer and adler32 are added' do
      blob = 'compressible' * (1024 * 4)
      compressed = described_class.deflate_chunk(blob)
      expect(compressed.bytesize).to be < blob.bytesize
      complete_deflated_segment = tag_deflated(compressed, blob)
      expect(Zlib.inflate(complete_deflated_segment)).to eq(blob)
    end

    it 'removes the header' do
      blob = 'compressible' * (1024 * 4)
      compressed = described_class.deflate_chunk(blob)
      expect(compressed[0..1]).not_to eq([120, 156].pack('C*'))
    end

    it 'removes the adler32' do
      blob = 'compressible' * (1024 * 4)
      compressed = described_class.deflate_chunk(blob)
      adler = [Zlib.adler32(blob)].pack('N')
      expect(compressed).not_to end_with(adler)
    end

    it 'removes the end marker' do
      blob = 'compressible' * (1024 * 4)
      compressed = described_class.deflate_chunk(blob)
      expect(compressed[-7..-5]).not_to eq([3, 0].pack('C*'))
    end

    it 'honors the compression level' do
      deflater = Zlib::Deflate.new
      expect(Zlib::Deflate).to receive(:new).with(2) { deflater }
      blob = 'compressible' * (1024 * 4)
      described_class.deflate_chunk(blob, level: 2)
    end
  end

  describe 'deflate_in_blocks_and_terminate' do
    it 'uses deflate_in_blocks' do
      data = 'compressible' * (1024 * 1024 * 10)
      input = StringIO.new(data)
      output = StringIO.new
      block_size = 1024 * 64
      expect(described_class).to receive(:deflate_in_blocks).with(input,
                                                                  output,
                                                                  level: -1,
                                                                  block_size: block_size).and_call_original
      described_class.deflate_in_blocks_and_terminate(input, output, block_size: block_size)
    end

    it 'passes a custom compression level' do
      data = 'compressible' * (1024 * 1024 * 10)
      input = StringIO.new(data)
      output = StringIO.new
      expect(described_class).to receive(:deflate_in_blocks).with(input,
                                                                  output,
                                                                  level: 9,
                                                                  block_size: 5_242_880).and_call_original
      described_class.deflate_in_blocks_and_terminate(input, output, level: Zlib::BEST_COMPRESSION)
    end

    it 'writes the end marker' do
      data = 'compressible' * (1024 * 1024 * 10)
      input = StringIO.new(data)
      output = StringIO.new
      described_class.deflate_in_blocks_and_terminate(input, output)
      expect(output.string[-2..-1]).to eq([3, 0].pack('C*'))
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
      data = 'compressible' * (1024 * 1024 * 10)
      input = StringIO.new(data)
      output = StringIO.new
      block_size = 1024 * 64

      num_chunks = (data.bytesize / block_size.to_f).ceil
      expect(described_class).to receive(:deflate_chunk).exactly(num_chunks).times.and_call_original
      expect(input).to receive(:read).with(block_size).exactly(num_chunks + 1).times.and_call_original
      expect(output).to receive(:<<).exactly(num_chunks).times.and_call_original

      described_class.deflate_in_blocks(input, output, block_size: block_size)
    end

    it 'does not write the end marker' do
      input_string = 'compressible' * (1024 * 1024 * 10)
      output_string = ''

      described_class.deflate_in_blocks(StringIO.new(input_string), StringIO.new(output_string))
      expect(output_string).not_to be_empty
      expect(output_string).not_to end_with([3, 0].pack('C*'))
    end

    it 'returns the number of bytes written' do
      input_string = 'compressible' * (1024 * 1024 * 10)
      output_string = ''

      num_bytes = described_class.deflate_in_blocks(StringIO.new(input_string),
                                                    StringIO.new(output_string))
      expect(num_bytes).to eq(245_016)
    end
  end
end
