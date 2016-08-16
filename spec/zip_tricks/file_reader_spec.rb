require 'spec_helper'

describe ZipTricks::FileReader do
  it 'reads and uncompresses the file written deflated with data descriptors' do
    zipfile = StringIO.new
    tolstoy = File.read(__dir__ + '/war-and-peace.txt')
    tolstoy.force_encoding(Encoding::BINARY)

    ZipTricks::Streamer.open(zipfile) do |zip|
      zip.write_deflated_file('war-and-peace.txt') do |sink|
        sink << tolstoy
      end
    end

    entries = described_class.read_zip_structure(zipfile)
    expect(entries.length).to eq(1)

    entry = entries.first

    readback = ''
    reader = entry.extractor_from(zipfile)
    readback << reader.extract(10) until reader.eof?

    expect(readback.bytesize).to eq(tolstoy.bytesize)
    expect(readback[0..10]).to eq(tolstoy[0..10])
    expect(readback[-10..-1]).to eq(tolstoy[-10..-1])
  end

  it 'reads the file written stored with data descriptors' do
    zipfile = StringIO.new
    tolstoy = File.read(__dir__ + '/war-and-peace.txt')
    ZipTricks::Streamer.open(zipfile) do |zip|
      zip.write_stored_file('war-and-peace.txt') do |sink|
        sink << tolstoy
      end
    end

    entries = described_class.read_zip_structure(zipfile)
    expect(entries.length).to eq(1)

    entry = entries.first

    readback = entry.extractor_from(zipfile).extract
    expect(readback.bytesize).to eq(tolstoy.bytesize)
    expect(readback[0..10]).to eq(tolstoy[0..10])
  end
  
  it 'is able to latch to the EOCD location even if the signature for the EOCD record appears all over the ZIP' do
    # A VERY evil ZIP file which has this signature all over
    eocd_sig = [0x06054b50].pack('V')
    evil_str = "#{eocd_sig} and #{eocd_sig}"
    
    z = StringIO.new
    w = ZipTricks::ZipWriter.new
    w.write_local_file_header(io: z, filename: evil_str, compressed_size: evil_str.bytesize,
       uncompressed_size: evil_str.bytesize, crc32: 0x06054b50, gp_flags: 0, mtime: Time.now, storage_mode: 0)
    z << evil_str
    where = z.tell
    w.write_central_directory_file_header(io: z, local_file_header_location: 0, gp_flags: 0, storage_mode: 0,
      filename: evil_str, compressed_size: evil_str.bytesize,
      uncompressed_size: evil_str.bytesize, mtime: Time.now, crc32: 0x06054b50)
    w.write_end_of_central_directory(io: z, start_of_central_directory_location: where,
      central_directory_size: z.tell - where, num_files_in_archive: 1, comment: evil_str)
    
    z.rewind
    entries = described_class.read_zip_structure(io: z)
    expect(entries.length).to eq(1)
  end
end
