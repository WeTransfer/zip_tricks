require_relative '../spec_helper'
require 'fileutils'
require 'shellwords'

describe ZipTricks::Microzip do
  # Run each test in a temporady directory, and nuke it afterwards
  around(:each) do |example|
    wd = Dir.pwd
    Dir.mktmpdir do | td |
      Dir.chdir(td)
      example.run
    end
    Dir.chdir(wd)
  end

  it 'creates an archive that can be opened by Rubyzip, with a small number of very tiny text files' do
    tf = ManagedTempfile.new('zip')
    z = described_class.new(tf)

    test_str = Random.new.bytes(64)
    crc = Zlib.crc32(test_str)
    t = Time.now.utc

    3.times do |i|
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
      expect(entries.length).to eq(3)
    end
    
    inspect_zip_with_external_tool(tf.path)
  end

  it 'raises an exception if the filename is non-unique in the already existing set' do
    z = described_class.new(StringIO.new)
    z.add_local_file_header(filename: 'foo.txt', crc32: 0, compressed_size: 0, uncompressed_size: 0, storage_mode: 0)
    expect {
      z.add_local_file_header(filename: 'foo.txt', crc32: 0, compressed_size: 0, uncompressed_size: 0, storage_mode: 0)
    }.to raise_error(/already/)
  end

  it 'raises an exception if the filename does not fit in 0xFFFF bytes' do
    longest_filename_in_the_universe = "x" * (0xFFFF + 1)
    z = described_class.new(StringIO.new)
    expect {
      z.add_local_file_header(filename: longest_filename_in_the_universe, crc32: 0, compressed_size: 0, uncompressed_size: 0, storage_mode: 0)
    }.to raise_error(/filename/)
  end

  it 'correctly sets the general-purpose flag bit 11 when a UTF-8 filename is passed in' do
    the_f = RandomFile.new(19)

    out_zip = ManagedTempfile.new('zip')
    z = described_class.new(out_zip)
    z.add_local_file_header(filename: 'тест', crc32: the_f.crc32, compressed_size: the_f.size,
      uncompressed_size: the_f.size, storage_mode: 0, mtime: Time.now)
    the_f.copy_to(out_zip)
    z.write_central_directory
    out_zip.flush

    Zip::File.open(out_zip.path) do |zip_file|
      entries = []
      zip_file.each do |entry|
        entries << entry
      end
      the_entry = entries[0]

      expect(the_entry.gp_flags).to eq(2048)
      expect(the_entry.name.force_encoding(Encoding::UTF_8)).to match(/тест/)
    end
  end

  it 'creates an archive with 1 5GB file (Zip64 due to a single file exceeding the size)', long: true do
    five_gigs = RandomFile.new(5 * 1024 * 1024 * 1024)

    out_zip = ManagedTempfile.new('huge-zip')
    z = described_class.new(out_zip)
    z.add_local_file_header(filename: 'the-five-gigs', crc32: five_gigs.crc32, compressed_size: five_gigs.size,
      uncompressed_size: five_gigs.size, storage_mode: 0, mtime: Time.now)
    five_gigs.copy_to(out_zip)
    z.write_central_directory
    out_zip.flush

    Zip::File.open(out_zip.path) do |zip_file|
      entries = []
      zip_file.each do |entry|
        entries << entry
        expect(entry.name).to match(/five/)
      end
      the_entry = entries[0]
      expect(the_entry.instance_variable_get("@version_needed_to_extract")).to eq(45) # Not accessible publicly
      expect(the_entry.compressed_size).to eq(5 * 1024 * 1024 * 1024)
      expect(the_entry.size).to eq(5 * 1024 * 1024 * 1024)
      expect(the_entry.instance_variable_get("@extra_length")).to be > 0 # Not accessible publicly
    end
    
    inspect_zip_with_external_tool(out_zip.path)
  end

  it 'creates an archive with 2 files each of which is just over 2GB (Zip64 due to offsets)', long: true do
    two_gigs_plus = RandomFile.new((2 * 1024 * 1024 * 1024) + 3)

    out_zip = ManagedTempfile.new('huge-zip')
    z = described_class.new(out_zip)

    z.add_local_file_header(filename: 'first', crc32: two_gigs_plus.crc32, compressed_size: two_gigs_plus.size,
      uncompressed_size: two_gigs_plus.size, storage_mode: 0, mtime: Time.now)
    two_gigs_plus.copy_to(out_zip)

    z.add_local_file_header(filename: 'second', crc32: two_gigs_plus.crc32, compressed_size: two_gigs_plus.size,
      uncompressed_size: two_gigs_plus.size, storage_mode: 0, mtime: Time.now)
    two_gigs_plus.copy_to(out_zip)

    z.write_central_directory
    out_zip.flush

    Zip::File.open(out_zip.path) do |zip_file|
      entries = []
      zip_file.each do |entry|
        entries << entry
      end
      expect(entries.length).to eq(2)
      first_entry, second_entry = entries[0], entries[1]
      
      expect(first_entry.extra_length).to be_zero # The file _itself_ is below 4GB
      expect(first_entry.size).to eq(two_gigs_plus.size)
      
      expect(second_entry.extra_length).to be_zero # The file _itself_ is below 4GB
      expect(second_entry.size).to eq(two_gigs_plus.size)
    end

    inspect_zip_with_external_tool(out_zip.path)
  end

  it 'creates an archive with more than 0xFFFF file entries (Zip64 due to number of files)', long: true do
    tf = ManagedTempfile.new('zip')
    z = described_class.new(tf)

    test_str = Random.new.bytes(64)
    crc = Zlib.crc32(test_str)
    t = Time.now.utc

    n_files = 0xFFFF + 6

    n_files.times do |i|
      fn = "test-#{i}.bin"
      still_alive!
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
