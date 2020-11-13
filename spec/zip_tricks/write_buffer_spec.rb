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

  it 'does not buffer with buffer size set to 0' do
    sink = double('Writable')

    expect(sink).to receive(:<<).with('a')
    expect(sink).to receive(:<<).with('b')

    adapter = described_class.new(sink, 0)
    adapter << 'a' << 'b'
  end

  it 'does not reuse the output string' do
    # It is important to ensure that when the accumulator writes into the
    # destination it does not write the same String object over and over, as
    # the receiving object might be retaining that String for later writes.
    accumulator = []
    write_buffer = described_class.new(accumulator, 2)
    write_buffer << "a" << "b" << "c" << "d" << "e" << "and a word" << "and more"
    write_buffer.flush

    expect(accumulator.join).to eq('abcdeand a wordand more')
    expect(accumulator.map(&:object_id).uniq.length).to eq(accumulator.length)
  end

  it 'bypasses the write if it is aligned to the buffer size' do
    accumulator = []
    write_buffer = described_class.new(accumulator, 3)
    buf = write_buffer.instance_variable_get(:@buf)
    expect(buf.size).to eq(0)
    write_buffer << "abcdef"
    expect(buf.size).to eq(0)
    write_buffer << "gh"
    expect(buf.size).to eq(2)
    write_buffer << "ijk"
    expect(buf.size).to eq(0)
    write_buffer << "lmno"
    expect(buf.size).to eq(1)
    write_buffer << "p"
    expect(buf.size).to eq(2)

    write_buffer.flush
    expect(accumulator).to eq(["abcdef", "gh", "ijk", "lmn", "op"])
  end

  it 'flushes the buffer and returns `to_i` from the contained object' do
    sink = double('Writable')

    expect(sink).to receive(:<<).with('quick brown fox ')
    expect(sink).to receive(:to_i).and_return(123)

    adapter = described_class.new(sink, 64 * 1024)
    'quick brown fox '.each_char do |char|
      adapter << char
    end

    expect(adapter.to_i).to eq(123)
  end
end
