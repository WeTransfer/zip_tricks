require_relative '../spec_helper'

describe 'Microzip in interop context' do
  let(:described_class) { ZipTricks::Microzip}
  
  it 'creates an archive that can be opened by Rubyzip, with a small number of very tiny text files' do
    tf = ManagedTempfile.new('zip')
    z = described_class.new(tf)

    test_str = Random.new.bytes(64)
    crc = Zlib.crc32(test_str)
    t = Time.now.utc

    3.times do |i|
      fn = "test-#{i}"
      z.add_local_file_header(filename: fn, crc32: crc, compressed_size: test_str.bytesize,
        uncompressed_size: test_str.bytesize, storage_mode: 0, mtime: t)
      tf << test_str
    end
    z.write_central_directory
    tf.flush

    Zip::File.open(tf.path) do |zip_file|
      entries = zip_file.to_a
      expect(entries.length).to eq(3)
      entries.each do |entry|
        # Make sure it is tagged as UNIX
        expect(entry.fstype).to eq(3)

        # Check the file contents
        readback = entry.get_input_stream.read
        readback.force_encoding(Encoding::BINARY)
        expect(readback).to eq(test_str)

        # The CRC
        expect(entry.crc).to eq(crc)

        # Check the name
        expect(entry.name).to match(/test/)

        # Check the right external attributes (non-executable on UNIX)
        expect(entry.external_file_attributes).to eq(2175008768)
      end
    end

    inspect_zip_with_external_tool(tf.path)
  end
end
