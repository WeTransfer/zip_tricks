require_relative '../spec_helper'
require 'fileutils'
require 'shellwords'

describe ZipTricks::Microzip do

  class RandomFile < Tempfile
    def initialize(size)
      super('random-bin')

    end
  end

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

  it 'creates an archive that can be opened by Rubyzip, with a small number of very tiny text files' do
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

    Zip::File.open(tf.path) do |zip_file|
      entries = []
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

  xit 'raises an exception if the filename is non-unique in the already existing set'
  it 'raises an exception if the filename does not fit in 0xFFFF bytes'
  it 'correctly sets the general-purpose flag bit 11 when a UTF-8 filename is passed in'
  it 'switches an entry to Zip64 if a file is added which, uncompreeed, is larger than the 4-byte max size'
  it 'switches an entry to Zip64 if a file is added which, compressed, is larger than the 4-byte max size'
  it 'switches an entry to Zip64 if a file is added which, compressed, is larger than the 4-byte max size'
  it 'creates an archive with 1 5GB file (Zip64 due to a single file exceeding the size)', long: true
  it 'creates an archive with 2 files each of which is just over 2GB (Zip64 due to offsets)', long: true

  it 'creates an archive with more than 0xFFFF file entries (Zip64 due to number of files)', long: true do
    tf = Tempfile.new('zip')
    z = described_class.new(tf)

    test_str = Random.new.bytes(64)
    crc = Zlib.crc32(test_str)
    t = Time.now.utc

    n_files = 0xFFFF + 6

    n_files.times do |i|
      fn = "test-#{i}.bin"
      z.add_local_file_header(filename: fn, crc32: crc, compressed_size: test_str.bytesize,
        uncompressed_size: test_str.bytesize, storage_mode: 0, mtime: t)
      tf << test_str
    end
    z.write_central_directory
    tf.flush

    Zip::File.open(tf.path) do |zip_file|
      entries = []
      zip_file.each do |entry|
        entries << entry
        expect(entry.name).to match(/test/)
      end
      expect(entries.length).to eq(n_files)
    end
  end
end
