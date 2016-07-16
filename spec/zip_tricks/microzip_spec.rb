require_relative '../spec_helper'
require 'fileutils'
require 'shellwords'

describe ZipTricks::Microzip do
  let(:test_text_file_path) {
    File.join(__dir__, 'war-and-peace.txt')
  }

  # Run each test in a temporady directory, and nuke it afterwards
  around(:each) do |example|
    wd = Dir.pwd
    Dir.mktmpdir do | td |
      Dir.chdir(td)
      example.run
    end
    Dir.chdir(wd)
  end

  def rewind_after(*ios)
    yield.tap { ios.map(&:rewind) }
  end

  it 'creates an archive with a number of very tiny text files' do
    tf = Tempfile.new('zip')
    z = described_class.new(tf)
    
    test_str = Random.new.bytes(64)
    crc = Zlib.crc32(test_str)
    t = Time.now.utc
    
    13.times do |i|
      fn = "test-#{i}.bin"
      z.add_local_file_header(filename: fn, crc32: crc, compressed_size: test_str.bytesize,
        uncompressed_size: test_str.bytesize, storage_mode: 0, mtime: t)
      tf << test_str
    end
    z.write_central_directory
    tf.flush
    
    entries = []
    Zip::File.open(tf.path) do |zip_file|
      zip_file.each do |entry|
        entries << entry
        readback = entry.get_input_stream.read
        readback.force_encoding(Encoding::BINARY)
        expect(readback).to eq(test_str)
        expect(entry.name).to match(/test/)
      end
      expect(entries.length).to eq(13)
    end
  end
end
