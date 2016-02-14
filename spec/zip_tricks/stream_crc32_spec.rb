require_relative '../spec_helper'

describe ZipTricks::StreamCRC32 do
  it 'computes the CRC32 of a large binary file' do
    raw = StringIO.new(SecureRandom.random_bytes(45 * 1024 * 1024))
    crc = Zlib.crc32(raw.string)
    via_from_io = described_class.from_io(raw)
    expect(via_from_io).to eq(crc)
  end
  
  it 'allows in-place updates' do
    raw = StringIO.new(SecureRandom.random_bytes(45 * 1024 * 1024))
    crc = Zlib.crc32(raw.string)
    
    stream_crc = described_class.new
    stream_crc << raw.read(1024 * 64) until raw.eof?
    expect(stream_crc.to_i).to eq(crc)
  end
  
  it 'supports chained shovel' do
    str = 'abcdef'
    crc = Zlib.crc32(str)
    
    stream_crc = described_class.new
    stream_crc << 'a' << 'b' << 'c' << 'd' << 'e' << 'f'
    
    expect(stream_crc.to_i).to eq(crc)
  end
  
  it 'allows in-place update with a known value' do
    crc = Zlib.crc32
    
    stream_crc = described_class.new
    stream_crc << "This is some data"
    stream_crc.append(45678, 12910)
    expect(stream_crc.to_i).to eq(1555667875)
  end
end
