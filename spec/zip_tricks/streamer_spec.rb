require_relative '../spec_helper'
require 'fileutils'

describe ZipTricks::Streamer do
  def rewind_after(*ios)
    yield.tap { ios.map(&:rewind) }
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
    
    wd = Dir.pwd
    Dir.mktmpdir do | td |
      Dir.chdir(td)
      output = `cp #{zip_file.path} test.zip && unzip test.zip`
      puts output.inspect
      `open test.zip`
    end
    Dir.chdir(wd)
  end

  
  it 'creates an archive that OSX ArchiveUtility can handle' do
    au_path = '/System/Library/CoreServices/Applications/Archive Utility.app/Contents/MacOS/Archive Utility'
    unless File.exist?(au_path)
      skip "This system does not have ArchiveUtility"
    end
    
    outbuf = Tempfile.new('zip')
    outbuf.binmode
    
    zip = ZipTricks::Streamer.new(outbuf)
    
    File.open(__dir__ + '/war-and-peace.txt', 'rb') do | source_f |
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
      `open osx-archive-test.zip` # This opens with ArchiveUtility
      sleep 3
      
      expect(File.size('osx-archive-test/war-and-peace.txt')).to eq(source_f.size)
      expect(File.size('osx-archive-test/war-and-peace-raw.txt')).to eq(source_f.size)
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
      output = `unzip #{zip_buf.path}`
      puts output.inspect
    end
    Dir.chdir(wd)
    
  end
end
