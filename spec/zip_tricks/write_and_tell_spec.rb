require_relative '../spec_helper'

describe ZipTricks::WriteAndTell do
  it 'maintains the count of bytes written' do
    blobs = []
    adapter = described_class.new('')
    expect(adapter.tell).to be_zero
    
    adapter << 'hello'
    adapter << ''
    adapter << '!'
    expect(adapter.tell).to eq(6)
  end
end
