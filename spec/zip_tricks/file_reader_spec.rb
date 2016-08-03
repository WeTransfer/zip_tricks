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
end
