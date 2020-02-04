require 'spec_helper'

describe ZipTricks::RemoteIO do
  let(:subject) { described_class.new('http://host.example/some.bin') }

  context 'when it internally addresses a remote resource' do
    it 'requests the size of the resource once via #request_object_size and \
        does neet to read if resource is empty' do
      expect(subject).to receive(:request_object_size).and_return(0)
      expect(subject.read).to be_nil
    end

    it 'performs remote reads when repeatedly requesting the same chunk, via \
        #request_range' do

      expect(subject).to receive(:request_object_size).and_return(120)
      allow(subject).to receive(:request_range) { |range|
        expect(range).to eq(5..14)
        Random.new.bytes(10)
      }
      20.times do
        subject.seek(5, IO::SEEK_SET)
        subject.read(10)
      end
    end
  end

  describe '#seek' do
    context 'with an unsupported mode' do
      it 'raises an error' do
        expect { subject.seek(123, :UNSUPPORTED) }.to raise_error(/unsupported/i)
      end
    end

    context 'with SEEK_SET mode' do
      it 'returns the offset of 10 when asked to seek to 10' do
        expect(subject).to receive(:request_object_size).and_return(100)
        mode = IO::SEEK_SET
        expect(subject.seek(10, mode)).to eq(0)
      end
    end
  end

  describe '#read' do
    before :each do
      @buf = Tempfile.new('simulated-http')
      @buf.binmode
      5.times { @buf << Random.new.bytes(1024 * 1024 * 3) }
      @buf.rewind

      allow(subject).to receive(:request_object_size).and_return(@buf.size)
      allow(subject).to receive(:request_range) { |range|
        @buf.read[range].tap { @buf.rewind }
      }
    end

    after :each do
      if @buf
        @buf.close
        @buf.unlink
      end
    end

    context 'without arguments' do
      it 'reads the entire buffer and alters the position pointer' do
        expect(subject.tell).to eq(0)
        read = subject.read
        expect(read.bytesize).to eq(@buf.size)
        expect(subject.tell).to eq(@buf.size)
      end
    end

    context 'with length' do
      it 'supports an unlimited number of reads of size 0 and does not perform \
          remote fetches for them' do
        expect(subject).not_to receive(:request_range)
        20.times do
          data = subject.read(0)
          expect(data).to eq('')
        end
      end

      it 'returns exact amount of bytes at the start of the buffer' do
        bytes_read = subject.read(10)
        expect(subject.tell).to eq(10)
        @buf.seek(0)
        expect(bytes_read).to eq(@buf.read(10))
      end

      it 'returns exact amount of bytes from the middle of the buffer' do
        subject.seek(456, IO::SEEK_SET)

        bytes_read = subject.read(10)
        expect(subject.tell).to eq(456 + 10)

        @buf.seek(456)
        expect(bytes_read).to eq(@buf.read(10))
      end

      it 'returns the last N bytes it can read' do
        at_end = @buf.size - 4
        subject.seek(at_end, IO::SEEK_SET)

        expect(subject.tell).to eq(15_728_636)
        bytes_read = subject.read(10)
        expect(subject.tell).to eq(@buf.size) # Should have moved the pos pointer to the end

        expect(bytes_read.bytesize).to eq(4)

        expect(subject.tell).to eq(@buf.size)
      end
    end
  end
end
