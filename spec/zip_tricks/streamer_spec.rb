require_relative '../spec_helper'
require 'fileutils'
require 'shellwords'

describe ZipTricks::Streamer do
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
  
  it 'raises an InvalidOutput if the given object does not support the methods' do
    expect {
      described_class.new(nil)
    }.to raise_error(ZipTricks::Streamer::InvalidOutput)
  end
  
  it 'returns the position in the IO at every call' do
    io = StringIO.new
    zip = described_class.new(io)
    pos = zip.add_compressed_entry('file.jpg', 182919, 8921, 8912)
    expect(pos).to eq(io.tell)
    expect(pos).to eq(38)
    
    retval = zip << SecureRandom.random_bytes(8912)
    expect(retval).to eq(zip)
    expect(io.tell).to eq(8950)
    
    pos = zip.add_stored_entry('file.jpg', 8921, 182919)
    expect(pos).to eq(8988)
    zip << SecureRandom.random_bytes(8921)
    expect(io.tell).to eq(17909)
    
    pos = zip.write_central_directory!
    expect(pos).to eq(io.tell)
    expect(pos).to eq(17985)
    
    pos_after_close = zip.close
    expect(pos_after_close).to eq(pos)
  end
  
  it 'can write and then read the block-deflated files' do
    f = Tempfile.new('raw')
    f.binmode
    
    rewind_after(f) do
      f << ('A' * 1024 * 1024)
      f << SecureRandom.random_bytes(1248)
      f << ('B' * 1024 * 1024)
    end
    
    crc = rewind_after(f) { Zlib.crc32(f.read) }
    
    compressed_blockwise = StringIO.new
    rewind_after(compressed_blockwise, f) do
      ZipTricks::BlockDeflate.deflate_in_blocks_and_terminate(f, compressed_blockwise, block_size: 1024)
    end
    
    # Perform the zipping
    zip_file = Tempfile.new('z')
    zip_file.binmode
    
    described_class.open(zip_file) do |zip|
      zip.add_compressed_entry("compressed-file.bin", f.size, crc, compressed_blockwise.size)
      zip << compressed_blockwise.read
    end
    zip_file.flush
    
    per_filename = {}
    Zip::File.open(zip_file.path) do |zip_file|
      # Handle entries one by one
      zip_file.each do |entry|
        # The entry name gets returned with a binary encoding, we have to force it back.
        per_filename[entry.name] = entry.get_input_stream.read
      end
    end
    
    expect(per_filename['compressed-file.bin'].bytesize).to eq(f.size)
    expect(Digest::SHA1.hexdigest(per_filename['compressed-file.bin'])).to eq(Digest::SHA1.hexdigest(f.read))
    
    output = `unzip -v #{zip_file.path}`
    puts output.inspect
  end

  
  it 'creates an archive that OSX ArchiveUtility can handle' do
    au_path = '/System/Library/CoreServices/Applications/Archive Utility.app/Contents/MacOS/Archive Utility'
    unless File.exist?(au_path)
      skip "This system does not have ArchiveUtility"
    end
    
    outbuf = Tempfile.new('zip')
    outbuf.binmode
    
    zip = ZipTricks::Streamer.new(outbuf)
    
    File.open(test_text_file_path, 'rb') do | source_f |
      crc32 = rewind_after(source_f) { Zlib.crc32(source_f.read) }
      
      compressed_buffer = StringIO.new
      
      expect(ZipTricks::BlockDeflate).to receive(:deflate_chunk).at_least(:twice).and_call_original
      
      # Compress in blocks of 4 Kb
      rewind_after(source_f, compressed_buffer) do
        ZipTricks::BlockDeflate.deflate_in_blocks_and_terminate(source_f, compressed_buffer, block_size: 1024 * 4)
      end
      
      # Add this file compressed...
      zip.add_compressed_entry('war-and-peace.txt', source_f.size, crc32, compressed_buffer.size)
      zip << compressed_buffer.string
      
      # ...and stored.
      zip.add_stored_entry('war-and-peace-raw.txt', source_f.size, crc32)
      zip << source_f.read
      
      zip.close
      
      outbuf.flush
      File.unlink('test.zip') rescue nil
      File.rename(outbuf.path, 'osx-archive-test.zip')
      
      # ArchiveUtility sometimes puts the stuff it unarchives in ~/Downloads etc. so do
      # not perform any checks on the files since we do not really know where they are on disk.
      # Visual inspection should show whether the unarchiving is handled correctly.
      `#{Shellwords.join([au_path, 'osx-archive-test.zip'])}`
    end
    
    FileUtils.rm_rf('osx-archive-test')
    FileUtils.rm_rf('osx-archive-test.zip')
  end
  
  it 'archives files which can then be read using the usual means with Rubyzip' do
    zip_buf = Tempfile.new('zipp')
    zip_buf.binmode
    output_io = double('IO')
    
    # Only allow the methods we provide in BlockWrite.
    # Will raise an error if other methods are triggered (the ones that
    # might try to rewind the IO).
    allow(output_io).to receive(:<<) {|data|
      zip_buf << data.to_s.force_encoding(Encoding::BINARY)
    }
    
    allow(output_io).to receive(:tell) { zip_buf.tell }
    allow(output_io).to receive(:pos) { zip_buf.pos }
    allow(output_io).to receive(:close)
    
    # Generate a couple of random files
    raw_file_1 = SecureRandom.random_bytes(1024 * 20)
    raw_file_2 = SecureRandom.random_bytes(1024 * 128)
    
    # Perform the zipping
    zip = described_class.new(output_io)
    zip.add_stored_entry("first-file.bin", raw_file_1.size, Zlib.crc32(raw_file_1))
    zip << raw_file_1
    zip.add_stored_entry("second-file.bin", raw_file_2.size, Zlib.crc32(raw_file_2))
    zip << raw_file_2
    zip.close
    
    zip_buf.flush
    
    per_filename = {}
    Zip::File.open(zip_buf.path) do |zip_file|
      # Handle entries one by one
      zip_file.each do |entry|
        # The entry name gets returned with a binary encoding, we have to force it back.
        # Somehow an empty string gets read
        per_filename[entry.name] = entry.get_input_stream.read
      end
    end
    
    expect(per_filename['first-file.bin'].unpack("C*")).to eq(raw_file_1.unpack("C*"))
    expect(per_filename['second-file.bin'].unpack("C*")).to eq(raw_file_2.unpack("C*"))
    
    wd = Dir.pwd
    Dir.mktmpdir do | td |
      Dir.chdir(td)
      output = `unzip -v #{zip_buf.path}`
      puts output.inspect
    end
    Dir.chdir(wd)
  end
  
  it 'sets the general-purpose flag for entries with UTF8 names' do
    zip_buf = Tempfile.new('zipp')
    zip_buf.binmode
    
    # Generate a couple of random files
    raw_file_1 = SecureRandom.random_bytes(1024 * 20)
    raw_file_2 = SecureRandom.random_bytes(1024 * 128)
    
    # Perform the zipping
    zip = described_class.new(zip_buf)
    zip.add_stored_entry("first-file.bin", raw_file_1.size, Zlib.crc32(raw_file_1))
    zip << raw_file_1
    zip.add_stored_entry("второй-файл.bin", raw_file_2.size, Zlib.crc32(raw_file_2))
    zip << raw_file_2
    zip.close
    
    zip_buf.flush
    
    entries = []
    Zip::File.open(zip_buf.path) do |zip_file|
      # Handle entries one by one
      zip_file.each {|entry| entries << entry }
      first_entry, second_entry = entries
      
      expect(first_entry.gp_flags).to eq(0)
      expect(first_entry.name).to eq('first-file.bin')
      
      # Rubyzip does not properly set the encoding of the entries it reads
      expect(second_entry.gp_flags).to eq(2048)
      expect(second_entry.name).to eq("второй-файл.bin".force_encoding(Encoding::BINARY))
    end
  end
  
  it 'raises when the actual bytes written for a stored entry does not match the entry header' do
    expect {
      ZipTricks::Streamer.open(StringIO.new) do | zip |
        zip.add_stored_entry('file', 123, 0)
        zip << 'xx'
      end
    }.to raise_error {|e|
      expect(e).to be_kind_of(ZipTricks::Streamer::EntryBodySizeMismatch)
      expect(e.message).to eq('Wrong number of bytes written for entry (expected 123, got 2)')
    }
  end

  it 'raises when the actual bytes written for a compressed entry does not match the entry header' do
    expect {
      ZipTricks::Streamer.open(StringIO.new) do | zip |
        zip.add_compressed_entry('file', 1898121, 0, 123)
        zip << 'xx'
      end
    }.to raise_error {|e|
      expect(e).to be_kind_of(ZipTricks::Streamer::EntryBodySizeMismatch)
      expect(e.message).to eq('Wrong number of bytes written for entry (expected 123, got 2)')
    }
  end
end
