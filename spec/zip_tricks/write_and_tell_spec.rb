require_relative '../spec_helper'

describe ZipTricks::WriteAndTell do
  it 'maintains the count of bytes written' do
    adapter = described_class.new('')
    expect(adapter.tell).to be_zero
    
    adapter << 'hello'
    adapter << ''
    adapter << '!'
    expect(adapter.tell).to eq(6)
  end
  
  it 'advances the internal pointer using advance_position_by' do
    str = ''
    
    adapter = described_class.new(str)
    expect(adapter.tell).to be_zero
    
    adapter << 'hello'
    adapter << ''
    adapter << '!'
    expect(adapter.tell).to eq(6)
    adapter.advance_position_by(128981)
    expect(adapter.tell).to eq(6 + 128981)
    expect(str).to eq('hello!')
  end
end
