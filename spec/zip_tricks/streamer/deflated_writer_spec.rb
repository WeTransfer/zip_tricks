require 'spec_helper'

describe ZipTricks::Streamer::DeflatedWriter do
  it 'deflates the data and computes the CRC32 checksum for it' do
    out = StringIO.new

    subject = ZipTricks::Streamer::DeflatedWriter.new(out)
    subject << ('a' * 256)
    subject << ('b' * 256)
    subject << ('b' * 256)

    finish_result = subject.finish

    zlib_inflater = ::Zlib::Inflate.new(-Zlib::MAX_WBITS)
    inflated = zlib_inflater.inflate(out.string)
    expect(inflated).to eq(('a' * 256) + ('b' * 256) + ('b' * 256))

    expect(finish_result).to eq(crc32: 234880044, compressed_size: out.size, uncompressed_size: 768)
  end
end
