require_relative '../spec_helper'

describe ZipTricks::BlockWrite do
  it 'calls the given block each time data is written' do
    blobs = []
    adapter = described_class.new { |s| blobs << s }

    adapter << 'hello'
    adapter << 'world'
    adapter << '!'

    expect(blobs).to eq(['hello', 'world', '!'])
  end

  it 'supports chained shovel' do
    blobs = []
    adapter = described_class.new { |s| blobs << s }

    adapter << 'hello' << 'world' << '!'

    expect(blobs).to eq(['hello', 'world', '!'])
  end

  it 'can write in all possible encodings, even if the strings are frozen' do
    accum_string = ''
    adapter = described_class.new { |s| accum_string << s }

    adapter << 'hello'
    adapter << 'привет'
    adapter << 'привет'.freeze
    adapter << '!'
    adapter << Random.new.bytes(1_024)

    expect(accum_string.bytesize).to eq(1_054)
  end

  it 'forces the written strings to binary encoding' do
    blobs = []
    adapter = described_class.new { |s| blobs << s }
    adapter << 'hello'.encode(Encoding::UTF_8)
    adapter << 'world'.encode(Encoding::BINARY)
    adapter << '!'
    expect(blobs).not_to be_empty
    blobs.each { |s| expect(s.encoding).to eq(Encoding::BINARY) }
  end

  it 'does not change the encoding of source strings' do
    hello = 'hello'.encode(Encoding::UTF_8)
    accum_string = ''.force_encoding(Encoding::BINARY)
    adapter = described_class.new { |s| accum_string << s }
    adapter << hello
    expect(accum_string.encoding).to eq(Encoding::BINARY)
    expect(hello.encoding).to eq(Encoding::UTF_8)
  end

  it 'omits strings of zero length' do
    blobs = []
    adapter = described_class.new { |s| blobs << s }
    adapter << 'hello'
    adapter << ''
    adapter << '!'
    expect(blobs).to eq(['hello', '!'])
  end

  it 'omits nils' do
    blobs = []
    adapter = described_class.new { |s| blobs << s }
    adapter << 'hello'
    adapter << nil
    adapter << '!'
    expect(blobs).to eq(['hello', '!'])
  end

  it 'raises a TypeError on specific unsupported methods' do
    adapter = described_class.new { |s| }
    expect { adapter.seek(123) }.to raise_error(/non\-rewindable/)

    expect { adapter.to_s }.to raise_error(/non\-rewindable/)

    expect { adapter.pos = 123 }.to raise_error(/non\-rewindable/)
  end
end
