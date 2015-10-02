require_relative '../spec_helper'

describe ZipTricks::OutputStreamPrefab do
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
    # Note this is commented out - because the header should be OMITTED!
    # compressed_blockwise << ZipTricks::BlockDeflate::HEADER
    rewind_after(compressed_blockwise, f) do
      adler = ZipTricks::BlockDeflate.compress_block(f, compressed_blockwise)
      compressed_blockwise << ZipTricks::BlockDeflate::END_MARKER
      compressed_blockwise << ZipTricks::BlockDeflate.pack_adler_int(adler)
    end
    
    # Perform the zipping
    zip_file = Tempfile.new('z')
    described_class.open(zip_file) do |zip|
      zip.put_next_entry("compressed-file.bin", f.size, crc, compressed_blockwise.size)
      zip << compressed_blockwise.read
    end
    
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
    described_class.open(output_io) do |zip|
      zip.put_next_entry("first-file.bin", raw_file_1.size, Zlib.crc32(raw_file_1))
      zip << raw_file_1
      zip.put_next_entry("second-file.bin", raw_file_2.size, Zlib.crc32(raw_file_2))
      zip << raw_file_2
    end
    
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
  end
end
