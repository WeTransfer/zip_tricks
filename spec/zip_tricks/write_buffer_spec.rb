require_relative '../spec_helper'

describe ZipTricks::WriteBuffer do
  it 'returns self from <<' do
    sink = []
    adapter = described_class.new(sink, 1024)
    expect(adapter << 'a').to eq(adapter)
  end

  it 'appends the written strings in one go for the set buffer size' do
    sink = double('Writable')

    expect(sink).to receive(:<<).with('quick brown fox ')
    expect(sink).to receive(:<<).with('jumps over the')
    
    adapter = described_class.new(sink, 'quick brown fox'.bytesize)
    'quick brown fox jumps over the'.split(//).each do |char|
      adapter << char
    end

    adapter.flush!
  end

  it 'flushes the buffer and returns `to_i` from the contained object' do
    sink = double('Writable')

    expect(sink).to receive(:<<).with('quick brown fox ')
    expect(sink).to receive(:to_i).and_return(123)

    adapter = described_class.new(sink, 64*1024)
    'quick brown fox '.split(//).each do |char|
      adapter << char
    end

    expect(adapter.to_i).to eq(123)
  end
end
