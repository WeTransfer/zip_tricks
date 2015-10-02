require_relative '../spec_helper'

describe ZipTricks::BlockDeflate do
  it 'compresses a big file and returns the adler32 checksums packed in a struct, makes data that can be inflated later' do
    file = Tempfile.new('t')
    
    big_str = 'A' * (1024 * 1024)
    11.times { file << big_str }
    
    file.rewind
    deflated = StringIO.new
    
    adler = described_class.compress_block(file, deflated)
    deflated << [3, 0].pack("C*") # Manually write the marker
    deflated << described_class.pack_adler_int(adler) # The final packed Adler value
    
    expect(deflated.size).to eq(11276)
    expect(adler).to eq(1888919151)
    
    # Write the resulting packed stream back into decompressable
    deflated.rewind
    
    # Use the same inflate method as Rubyzip
    inflater = ::Zlib::Inflate.new(-Zlib::MAX_WBITS)
    inflated = inflater.inflate(deflated.read)
    
    file.rewind
    ref_content = file.read
    
    expect(inflated.bytesize).to eq(ref_content.bytesize)
    expect(Digest::SHA1.hexdigest(inflated)).to eq(Digest::SHA1.hexdigest(ref_content))
  end
end
