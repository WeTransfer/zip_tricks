require_relative '../spec_helper'

describe ZipTricks::BlockWrite do
  it 'calls the given block each time data is written' do
    blobs = []
    adapter = described_class.new{|s|
      blobs << s
    }
    
    adapter << 'hello'
    adapter << 'world'
    adapter << '!'
    
    expect(blobs).to eq(['hello', 'world', '!'])
  end
  
  it 'forces the written strings to binary encoding' do
    blobs = []
    adapter = described_class.new{|s|
      blobs << s
    }
    adapter << 'hello'.encode(Encoding::UTF_8)
    adapter << 'world'.encode(Encoding::BINARY)
    adapter << '!'
    expect(blobs).not_to be_empty
    blobs.each {|s| expect(s.encoding).to eq(Encoding::BINARY) }
  end
  
  it 'omits strings of zero length' do
    blobs = []
    adapter = described_class.new{|s|
      blobs << s
    }
    adapter << 'hello'
    adapter << ''
    adapter << '!'
    expect(blobs).to eq(['hello', '!'])
  end
  
  it 'omits nils' do
    blobs = []
    adapter = described_class.new{|s|
      blobs << s
    }
    adapter << 'hello'
    adapter << nil
    adapter << '!'
    expect(blobs).to eq(['hello', '!'])
  end
  
  it 'maintains the count of bytes written' do
    blobs = []
    adapter = described_class.new{|s|
      blobs << s
    }
    expect(adapter.tell).to be_zero
    
    adapter << 'hello'
    adapter << ''
    adapter << '!'
    expect(adapter.tell).to eq(6)
  end
  
  it 'raises a TypeError on specific unsupported methods' do
    adapter = described_class.new {|s| }
    expect {
      adapter.seek(123)
    }.to raise_error(/non\-rewindable/)
    
    expect {
      adapter.to_s
    }.to raise_error(/non\-rewindable/)
    
    expect {
      adapter.pos = 123
    }.to raise_error(/non\-rewindable/)
  end
end
