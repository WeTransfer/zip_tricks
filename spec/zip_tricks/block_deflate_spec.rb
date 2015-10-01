require_relative '../spec_helper'

describe ZipTricks::BlockDeflate do
  it 'compresses a big file and returns the adler32 checksums packed in a struct' do
    file = Tempfile.new('t')
    
    big_str = 'A' * (1024 * 1024)
    11.times { file << big_str }
    
    file.rewind
    deflated = StringIO.new
    
    adler = described_class.compress_block(file, deflated, write_header = true)
    file.rewind; deflated.rewind
    
    expect(deflated.size).to eq(11442)
    expect(adler).to eq(1888919151)
    
    # Write the resulting packed stream back into decompressable
    decompressable = StringIO.new
    decompressable << deflated.read # Contains the header written with the first part, afterwards it is only block one after another
    decompressable << described_class::END_MARKER
    decompressable << [adler].pack("N") # The final packed Adler value
    
    decompressable.rewind
    inflated = Zlib.inflate(decompressable.read)
    expect(inflated.bytesize).to eq(file.size)
  end
end
