require_relative '../spec_helper'

describe ZipTricks::WriteBuffer do
  it 'returns self from <<' do
    sink = []
    adapter = described_class.new(sink, 1024)
    expect(adapter << 'a').to eq(adapter)
  end

  it 'appends the written strings in one go for the set buffer size' do
    sink = double('Writable')

    expect(sink).to receive(:<<).with('quick brown fox')
    expect(sink).to receive(:<<).with(' jumps over the')

    adapter = described_class.new(sink, 'quick brown fox'.bytesize)
    'quick brown fox jumps over the'.each_char do |char|
      adapter << char
    end

    adapter.flush
  end

  it 'bypasses larger writes, even if the amount of data accumulated is smaller than bufsize' do
    # The WriteBuffer reuses strings, so examining its output is easier via Arrays
    # if duplication gets applied on every write
    class Duplicator < Struct.new(:accumulator)
      def <<(data)
        accumulator << data.dup
        self
      end
    end

    accumulator = []
    subject = described_class.new(Duplicator.new(accumulator), 12)
    subject << 'one'
    subject << 'a much larger larger larger string which  is larger than the buffer size'
    subject << 'some more data'
    subject.flush

    expect(accumulator).to eq([
      "one",
      "a much larger larger larger string which  is larger than the buffer size",
      "some more data"
    ])
  end

  it 'reuses the same String object throughout writes to conserve allocations' do
    accumulator = []
    subject = described_class.new(accumulator, 12)
    subject << 'a' << 'b' << 'c'
    subject.flush
    subject << 'd'
    subject.flush

    # The accumulator contains 2 references to the same internal String in the WriteBuffer,
    # and it gets cleared after every flush of the buffer
    expect(accumulator).to eq(["", ""])
  end

  it 'supports flush! in addition to flush' do
    sink = double('Writable')

    expect(sink).to receive(:<<).with('ab')

    adapter = described_class.new(sink, 64)
    adapter << 'a' << 'b'
    adapter.flush!
  end

  it 'does not buffer with buffer size set to 0' do
    sink = double('Writable')

    expect(sink).to receive(:<<).with('a')
    expect(sink).to receive(:<<).with('b')

    adapter = described_class.new(sink, 0)
    adapter << 'a' << 'b'
  end

  it 'flushes the buffer when asked' do
    sink = double('Writable')

    expect(sink).to receive(:<<).with('quick brown fox ')

    adapter = described_class.new(sink, 64 * 1024)

    'quick brown fox '.each_char do |char|
      adapter << char
    end
    adapter.flush
  end
end
