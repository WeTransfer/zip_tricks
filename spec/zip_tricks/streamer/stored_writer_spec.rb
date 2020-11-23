require 'spec_helper'

describe ZipTricks::Streamer::StoredWriter do
  it 'deflates the data and computes the CRC32 checksum for it' do
    out = StringIO.new

    subject = ZipTricks::Streamer::StoredWriter.new(out)
    subject << ('a' * 256)
    subject << ('b' * 256)
    subject << ('b' * 256)

    finish_result = subject.finish

    expect(out.string).to eq(('a' * 256) + ('b' * 256) + ('b' * 256))

    expect(finish_result).to eq(crc32: 234880044, compressed_size: 768, uncompressed_size: 768)
  end
end
