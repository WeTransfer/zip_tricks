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
