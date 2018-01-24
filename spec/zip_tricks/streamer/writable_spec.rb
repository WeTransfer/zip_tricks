require_relative '../../spec_helper'

describe ZipTricks::Streamer::Writable do
  describe '#<<' do
    it 'writes the given data to the destination and returns self' do
      buf = StringIO.new
      subject = described_class.new(double('streamer'), buf)

      result = subject << 'hello!'

      expect(buf.string).to eq('hello!')
      expect(result).to eq(subject)
    end

    it 'raises if the write is attempted after closing' do
      fake_deflater = double(finish: {})
      fake_streamer = double(update_last_entry_and_write_data_descriptor: 0)
      subject = described_class.new(fake_streamer, fake_deflater)

      subject.close
      expect { subject << 'foo' }.to raise_error(/closed/)
    end
  end

  describe '#close' do
    it 'finishes the writer and writes data descriptor on the Streamer' do
      streamer = double('Streamer')
      expect(streamer).to receive(:update_last_entry_and_write_data_descriptor).with(crc32: 1,
                                                                                     compressed_size: 2,
                                                                                     uncompressed_size: 3)
      deflater = double('Deflater')
      expect(deflater).to receive(:finish).and_return(crc32: 1, compressed_size: 2, uncompressed_size: 3)

      described_class.new(streamer, deflater).close
    end

    it 'does not write the data descriptor twice' do
      streamer = double
      deflater = double
      expect(streamer).to receive(:update_last_entry_and_write_data_descriptor).once
      expect(deflater).to receive(:finish).once.and_return({})

      subject = described_class.new(streamer, deflater)
      4.times { subject.close }
    end
  end

  describe '#write' do
    it 'writes the given data to the destination and returns the number of bytes written' do
      buf = StringIO.new
      subject = described_class.new(double('streamer'), buf)

      result = subject.write('hello!')

      expect(buf.string).to eq('hello!')
      expect(result).to eq(6)
    end
  end
end
