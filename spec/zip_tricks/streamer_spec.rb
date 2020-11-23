require_relative '../spec_helper'
require 'complexity_assert'

describe ZipTricks::Streamer do
  let(:test_text_file_path) { File.join(__dir__, 'war-and-peace.txt') }

  # Run each test in a temporady directory, and nuke it afterwards
  around(:each) do |example|
    wd = Dir.pwd
    Dir.mktmpdir do |td|
      Dir.chdir(td)
      example.run
    end
    Dir.chdir(wd)
  end

  def rewind_after(*ios)
    yield.tap { ios.map(&:rewind) }
  end

  class FakeZipWriter
    def write_local_file_header(*);               end

    def write_data_descriptor(*);                 end

    def write_central_directory_file_header(*);   end

    def write_end_of_central_directory(*);        end
  end

  it 'has linear performance depending on the file count' do
    module FilecountComplexity
      def self.generate_args(size)
        [size]
      end

      def self.run(n_files)
        ZipTricks::Streamer.open(ZipTricks::NullWriter, writer: FakeZipWriter.new) do |w|
          n_files.times do |i|
            w.write_stored_file(format('file_%d', i)) { |body| body << 'w' }
          end
        end
      end
    end

    expect(FilecountComplexity).to be_linear
  end

  it 'raises an InvalidOutput if the given object does not support the methods' do
    expect { described_class.new(nil) }.to raise_error(ZipTricks::Streamer::InvalidOutput)
  end

  it 'allows the writer to be injectable' do
    fake_writer = double('ZipWriter')
    expect(fake_writer).to receive(:write_local_file_header)
    expect(fake_writer).to receive(:write_data_descriptor)
    expect(fake_writer).to receive(:write_central_directory_file_header)
    expect(fake_writer).to receive(:write_end_of_central_directory)

    described_class.open('', writer: fake_writer) do |zip|
      zip.write_deflated_file('stored.txt') do |sink|
        sink << File.read(__dir__ + '/war-and-peace.txt')
      end
    end
  end

  it 'returns the position in the IO at every call' do
    io = StringIO.new
    zip = described_class.new(io)
    pos = zip.add_deflated_entry(filename: 'file.jpg',
                                 uncompressed_size: 182_919,
                                 compressed_size: 8_912,
                                 crc32: 8_912)
    expect(pos).to eq(io.tell)
    expect(pos).to eq(47)

    retval = zip << Random.new.bytes(8_912)
    expect(retval).to eq(zip)
    expect(io.tell).to eq(8_959)

    pos = zip.add_stored_entry(filename: 'filf.jpg', size: 8_921, crc32: 182_919)
    expect(pos).to eq(9006)
    zip << Random.new.bytes(8_921)
    expect(io.tell).to eq(17_927)

    pos = zip.close
    expect(pos).to eq(io.tell)
    expect(pos).to eq(18_104)
  end

  it 'can write and then read the block-deflated files' do
    f = Tempfile.new('raw')
    f.binmode

    rewind_after(f) do
      f << ('A' * 1_024 * 1_024)
      f << Random.new.bytes(1_248)
      f << ('B' * 1_024 * 1_024)
    end

    crc = rewind_after(f) { Zlib.crc32(f.read) }

    compressed_blockwise = StringIO.new
    rewind_after(compressed_blockwise, f) do
      ZipTricks::BlockDeflate.deflate_in_blocks_and_terminate(f,
                                                              compressed_blockwise,
                                                              block_size: 1_024)
    end

    # Perform the zipping
    zip_file = Tempfile.new('z')
    zip_file.binmode

    described_class.open(zip_file) do |zip|
      zip.add_deflated_entry(filename: 'compressed-file.bin',
                             uncompressed_size: f.size,
                             crc32: crc,
                             compressed_size: compressed_blockwise.size)
      zip << compressed_blockwise.read
    end
    zip_file.flush

    per_filename = {}
    Zip::File.open(zip_file.path) do |zipfile|
      # Handle entries one by one
      zipfile.each do |entry|
        # The entry name gets returned with a binary encoding, we have to force it back.
        per_filename[entry.name] = entry.get_input_stream.read
      end
    end

    expect(per_filename['compressed-file.bin'].bytesize).to eq(f.size)
    expect(Digest::SHA1.hexdigest(per_filename['compressed-file.bin'])).to \
      eq(Digest::SHA1.hexdigest(f.read))

    inspect_zip_with_external_tool(zip_file.path)
  end

  it 'can write and then read an empty directory' do
    # Perform the zipping
    zip_file = Tempfile.new('z')
    zip_file.binmode

    described_class.open(zip_file) do |zip|
      zip.add_empty_directory(dirname: 'Tunes')
    end
    zip_file.flush

    per_filename = {}

    Zip::File.open(zip_file.path) do |zipfile|
      # Handle entries one by one
      zipfile.each do |entry|
        # The entry name gets returned with a binary encoding, we have to force it back.
        per_filename[entry.name] = entry.get_raw_input_stream.read
      end
    end

    expect(per_filename['Tunes/'].bytesize).to eq(157)

    inspect_zip_with_external_tool(zip_file.path)
  end

  it 'can write the data descriptor and updates the last entry as well' do
    out = StringIO.new
    fake_w = double('Writer')
    expect(fake_w).to receive(:write_local_file_header)
    expect(fake_w).to receive(:write_data_descriptor)
    expect(fake_w).to receive(:write_central_directory_file_header)
    expect(fake_w).to receive(:write_end_of_central_directory)

    file_contents = 'Some data from file'
    crc = Zlib.crc32('Some data from file')

    ZipTricks::Streamer.open(out, writer: fake_w) do |zip|
      zip.add_stored_entry(filename: 'somefile.txt', use_data_descriptor: true)
      zip << file_contents
      zip.update_last_entry_and_write_data_descriptor(crc32: crc,
                                                      compressed_size: file_contents.bytesize,
                                                      uncompressed_size: file_contents.bytesize)
    end
  end

  it 'archives files which can then be read using the usual means with Rubyzip' do
    zip_buf = Tempfile.new('zipp')
    zip_buf.binmode
    output_io = double('IO')

    # Only allow the methods we provide in BlockWrite.
    # Will raise an error if other methods are triggered (the ones that
    # might try to rewind the IO).
    allow(output_io).to receive(:<<) { |data|
      zip_buf << data.to_s.force_encoding(Encoding::BINARY)
    }

    allow(output_io).to receive(:tell) { zip_buf.tell }
    allow(output_io).to receive(:pos) { zip_buf.pos }
    allow(output_io).to receive(:close)

    # Generate a couple of random files
    raw_file1 = Random.new.bytes(1024 * 20)
    raw_file2 = Random.new.bytes(1024 * 128)

    # Perform the zipping
    zip = described_class.new(output_io)
    zip.add_stored_entry(filename: 'first-file.bin',
                         size: raw_file1.size,
                         crc32: Zlib.crc32(raw_file1))
    zip << raw_file1
    zip.add_stored_entry(filename: 'second-file.bin',
                         size: raw_file2.size,
                         crc32: Zlib.crc32(raw_file2))
    zip << raw_file2
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

    expect(per_filename['first-file.bin'].unpack('C*')).to eq(raw_file1.unpack('C*'))
    expect(per_filename['second-file.bin'].unpack('C*')).to eq(raw_file2.unpack('C*'))

    wd = Dir.pwd
    Dir.mktmpdir do |td|
      Dir.chdir(td)
      inspect_zip_with_external_tool(zip_buf.path)
    end
    Dir.chdir(wd)
  end

  it 'sets the general-purpose flag for entries with UTF8 names' do
    zip_buf = Tempfile.new('zipp')
    zip_buf.binmode

    # Generate a couple of random files
    raw_file1 = Random.new.bytes(1_024 * 20)
    raw_file2 = Random.new.bytes(1_024 * 128)

    # Perform the zipping
    zip = described_class.new(zip_buf)
    zip.add_stored_entry(filename: 'first-file.bin',
                         size: raw_file1.size,
                         crc32: Zlib.crc32(raw_file1))
    zip << raw_file1
    zip.add_stored_entry(filename: 'второй-файл.bin',
                         size: raw_file2.size,
                         crc32: Zlib.crc32(raw_file2))
    IO.copy_stream(StringIO.new(raw_file2), zip)
    zip.close

    zip_buf.flush

    entries = []
    Zip::File.open(zip_buf.path) do |zip_file|
      # Handle entries one by one
      zip_file.each { |entry| entries << entry }
      first_entry, second_entry = entries

      expect(first_entry.gp_flags).to eq(0)
      expect(first_entry.name).to eq('first-file.bin')

      # Rubyzip does not properly set the encoding of the entries it reads
      expect(second_entry.gp_flags).to eq(2_048)
      expect(second_entry.name).to eq('второй-файл.bin'.force_encoding(Encoding::BINARY))
    end
  end

  it 'writes the correct archive elements when using data descriptors' do
    out = StringIO.new
    fake_w = double('Writer')
    expect(fake_w).to receive(:write_local_file_header) { |**kwargs|
      expect(kwargs[:storage_mode]).to eq(8)
      expect(kwargs[:crc32]).to be_zero
      expect(kwargs[:filename]).to eq('somefile.txt')
    }
    expect(fake_w).to receive(:write_data_descriptor) { |**kwargs|
      expect(kwargs[:crc32]).to eq(2729945713)
      expect(kwargs[:compressed_size]).to eq(19)
      expect(kwargs[:uncompressed_size]).to eq(17)
    }
    expect(fake_w).to receive(:write_local_file_header) { |**kwargs|
      expect(kwargs[:storage_mode]).to eq(0)
      expect(kwargs[:crc32]).to be_zero
      expect(kwargs[:filename]).to eq('uncompressed.txt')
    }
    expect(fake_w).to receive(:write_data_descriptor) { |**kwargs|
      expect(kwargs[:crc32]).to eq(1550572917)
      expect(kwargs[:compressed_size]).to eq(22)
      expect(kwargs[:uncompressed_size]).to eq(22)
    }
    expect(fake_w).to receive(:write_central_directory_file_header) { |**kwargs|
      expect(kwargs[:local_file_header_location]).to eq(0)
      expect(kwargs[:filename]).to eq('somefile.txt')
      expect(kwargs[:gp_flags]).to eq(8)
      expect(kwargs[:storage_mode]).to eq(8)
      expect(kwargs[:compressed_size]).to eq(19)
      expect(kwargs[:uncompressed_size]).to eq(17)
      expect(kwargs[:crc32]).to eq(2729945713)
      kwargs[:io] << 'fake'
    }
    expect(fake_w).to receive(:write_central_directory_file_header) { |**kwargs|
      expect(kwargs[:local_file_header_location]).to eq(19)
      expect(kwargs[:filename]).to eq('uncompressed.txt')
      expect(kwargs[:gp_flags]).to eq(8)
      expect(kwargs[:storage_mode]).to eq(0)
      expect(kwargs[:compressed_size]).to eq(22)
      expect(kwargs[:uncompressed_size]).to eq(22)
      expect(kwargs[:crc32]).to eq(1550572917)
      kwargs[:io] << 'fake'
    }
    expect(fake_w).to receive(:write_end_of_central_directory) { |**kwargs|
      expect(kwargs[:start_of_central_directory_location]).to be > 0
      expect(kwargs[:central_directory_size]).to be > 0
      expect(kwargs[:num_files_in_archive]).to eq(2)
    }

    ZipTricks::Streamer.open(out, writer: fake_w) do |z|
      z.write_deflated_file('somefile.txt') do |out|
        out << 'Experimental data'
      end
      z.write_stored_file('uncompressed.txt') do |out|
        out << 'Some uncompressed data'
      end
    end
  end

  it 'allows the yielded writable sinks to be closed twice even when using a block' do
    out = StringIO.new
    fake_w = double('Writer')
    expect(fake_w).to receive(:write_local_file_header)
    expect(fake_w).to receive(:write_data_descriptor)
    expect(fake_w).to receive(:write_local_file_header)
    expect(fake_w).to receive(:write_data_descriptor)
    expect(fake_w).to receive(:write_central_directory_file_header)
    expect(fake_w).to receive(:write_central_directory_file_header)
    expect(fake_w).to receive(:write_end_of_central_directory)

    ZipTricks::Streamer.open(out, writer: fake_w) do |z|
      z.write_deflated_file('somefile.txt', &:close)
      z.write_stored_file('uncompressed.txt', &:close)
    end
  end

  it 'supports deferred writes using the return values from write_deflated_file and write_stored_file' do
    out = StringIO.new
    fake_w = double('Writer')
    expect(fake_w).to receive(:write_local_file_header)
    expect(fake_w).to receive(:write_data_descriptor)
    expect(fake_w).to receive(:write_local_file_header)
    expect(fake_w).to receive(:write_data_descriptor)
    expect(fake_w).to receive(:write_central_directory_file_header)
    expect(fake_w).to receive(:write_central_directory_file_header)
    expect(fake_w).to receive(:write_end_of_central_directory)

    ZipTricks::Streamer.open(out, writer: fake_w) do |z|
      out = z.write_deflated_file('somefile.txt')
      out << 'Experimental data'
      out.close

      out = z.write_stored_file('uncompressed.txt')
      out << 'Some uncompressed data'
      out.close
    end
  end

  it 'creates an archive with data descriptors that can be opened by Rubyzip, with a small number of very tiny text files' do
    tf = ManagedTempfile.new('zip')
    described_class.open(tf) do |zip|
      zip.write_stored_file('stored.txt') do |sink|
        sink << File.binread(__dir__ + '/war-and-peace.txt')
      end
      zip.write_deflated_file('deflated.txt') do |sink|
        sink << File.binread(__dir__ + '/war-and-peace.txt')
      end
    end
    tf.flush

    Zip::File.foreach(tf.path) do |entry|
      # Make sure it is tagged as UNIX
      expect(entry.fstype).to eq(3)

      # The CRC
      expect(entry.crc).to eq(Zlib.crc32(File.binread(__dir__ + '/war-and-peace.txt')))

      # Check the name
      expect(entry.name).to match(/\.txt$/)

      # Check the right external attributes (non-executable on UNIX)
      expect(entry.external_file_attributes).to eq(2_175_008_768)

      # Check the file contents
      readback = entry.get_input_stream.read
      readback.force_encoding(Encoding::BINARY)
      expect(readback[0..10]).to eq(File.binread(__dir__ + '/war-and-peace.txt')[0..10])
    end

    inspect_zip_with_external_tool(tf.path)
  end

  it 'can create a valid ZIP archive without any files' do
    tf = ManagedTempfile.new('zip')

    described_class.open(tf) do |zip|
    end

    tf.flush
    tf.rewind

    expect { |b| Zip::File.foreach(tf.path, &b) }.not_to yield_control
  end

  it 'prevents duplicates in the stored files' do
    files = [
      'README', 'README', 'file.one\\two.jpg', 'file_one.jpg', 'file_one (1).jpg',
      'file\\one.jpg', 'My.Super.file.txt.zip', 'My.Super.file.txt.zip'
    ]
    fake_writer = double('Writer').as_null_object
    seen_filenames = []
    allow(fake_writer).to receive(:write_local_file_header) { |filename:, **_others|
      seen_filenames << filename
    }
    zip_streamer = described_class.new(StringIO.new, writer: fake_writer, auto_rename_duplicate_filenames: true)
    files.each do |fn|
      zip_streamer.add_stored_entry(filename: fn, size: 1_024, crc32: 0xCC)
    end
    expect(seen_filenames).to eq([
      'README', 'README (1)', 'file.one_two.jpg', 'file_one.jpg',
      'file_one (1).jpg', 'file_one (2).jpg', 'My.Super.file.txt.zip',
      'My.Super.file (1).txt.zip'
    ])
  end

  it 'raises when a file would clobber a directory or vice versa (without automatic deduping)' do
    expect {
      zip_streamer = described_class.new(StringIO.new, auto_rename_duplicate_filenames: false)
      zip_streamer.add_empty_directory(dirname: 'foo/bar/baz')
      zip_streamer.add_stored_entry(filename: 'foo/bar/baz', size: 1_024, crc32: 0xCC)
    }.to raise_error(ZipTricks::PathSet::Conflict)

    expect {
      zip_streamer = described_class.new(StringIO.new, auto_rename_duplicate_filenames: false)
      zip_streamer.add_empty_directory(dirname: 'foo/bar/baz')
      zip_streamer.add_deflated_entry(filename: 'foo/bar/baz', compressed_size: 1_024, uncompressed_size: 12548, crc32: 0xCC)
    }.to raise_error(ZipTricks::PathSet::Conflict)

    expect {
      zip_streamer = described_class.new(StringIO.new, auto_rename_duplicate_filenames: false)
      zip_streamer.add_stored_entry(filename: 'foo/bar/baz', size: 1_024, crc32: 0xCC)
      zip_streamer.add_empty_directory(dirname: 'foo/bar/baz')
    }.to raise_error(ZipTricks::PathSet::Conflict)

    expect {
      zip_streamer = described_class.new(StringIO.new, auto_rename_duplicate_filenames: false)
      zip_streamer.add_stored_entry(filename: 'foo/bar/baz', size: 1_024, crc32: 0xCC)
      zip_streamer.add_stored_entry(filename: 'foo/bar/baz/bad', size: 1_024, crc32: 0xCC)
    }.to raise_error(ZipTricks::PathSet::Conflict)

    expect {
      zip_streamer = described_class.new(StringIO.new, auto_rename_duplicate_filenames: false)
      zip_streamer.add_stored_entry(filename: 'a/b', size: 1_024, crc32: 0xCC)
      zip_streamer.add_empty_directory(dirname: 'a/b/c')
    }.to raise_error(ZipTricks::PathSet::Conflict)

    expect {
      zip_streamer = described_class.new(StringIO.new, auto_rename_duplicate_filenames: false)
      zip_streamer.add_empty_directory(dirname: 'a/b/c')
      zip_streamer.add_stored_entry(filename: 'a/b', size: 1_024, crc32: 0xCC)
    }.to raise_error(ZipTricks::PathSet::Conflict)
  end

  it 'raises when a file would clobber another file (without automatic deduping)' do
    fake_writer = double('Writer').as_null_object
    expect {
      zip_streamer = described_class.new(StringIO.new, writer: fake_writer, auto_rename_duplicate_filenames: false)
      zip_streamer.add_stored_entry(filename: 'foo/bar/baz', size: 1_024, crc32: 0xCC)
      zip_streamer.add_stored_entry(filename: 'foo/bar/baz', size: 14, crc32: 0x0C)
    }.to raise_error(ZipTricks::PathSet::Conflict)

    expect {
      zip_streamer = described_class.new(StringIO.new, writer: fake_writer, auto_rename_duplicate_filenames: false)
      zip_streamer.add_stored_entry(filename: 'foo', size: 1_024, crc32: 0xCC)
      zip_streamer.add_stored_entry(filename: 'foo', size: 14, crc32: 0x0C)
    }.to raise_error(ZipTricks::PathSet::Conflict)
  end

  it 'raises when a file would clobber a directory or vice versa (when automatic filename deduplication is enabled)' do
    fake_writer = double('Writer').as_null_object
    expect {
      zip_streamer = described_class.new(StringIO.new, writer: fake_writer, auto_rename_duplicate_filenames: true)
      zip_streamer.add_stored_entry(filename: 'foo/bar/baz', size: 1_024, crc32: 0xCC)
      zip_streamer.add_stored_entry(filename: 'foo/bar/baz/bad', size: 1_024, crc32: 0xCC)
    }.to raise_error(ZipTricks::PathSet::Conflict)

    # Contrary to what one would think, the order in which entries get added in this instance matters.
    # When the "outer" file with a conflicting name gets created first, and the file which is inside
    # that path gets created later, the "shorter" path will be deduplicated (the last element will be
    # changed to "baz (1)" to avoid conflict). This is certainly usable, but is _magic_ behavior -
    # which is one of the reasons why automatically fixing non-unique filenames is a bad idea,
    # and we are going to make it optional - it can lead to very non-intuitive behavior
    expect {
      zip_streamer = described_class.new(StringIO.new, writer: fake_writer, auto_rename_duplicate_filenames: true)
      zip_streamer.add_stored_entry(filename: 'foo/bar/baz/bad', size: 1_024, crc32: 0xCC)
      zip_streamer.add_stored_entry(filename: 'foo/bar/baz', size: 1_024, crc32: 0xCC)
      # The error raised would be ZipTricks::PathSet::Conflict but RSpec reasonably advises not using
      # not_to raise_error(ZipTricks::PathSet::Conflict) due to the semantics of raise_error
    }.not_to raise_error
  end

  it 'raises when the IO offset is out of sync with the sizes of the entries known to the Streamer' do
    expect {
      described_class.open(StringIO.new, auto_rename_duplicate_filenames: false) do |zip_streamer|
        zip_streamer.add_stored_entry(filename: 'foo/bar/baz', size: 1_024, crc32: 0xCC)
      end
    }.to raise_error(ZipTricks::Streamer::OffsetOutOfSync, /Entries add up to \d+ bytes and the IO is at 50 bytes/)
  end

  it 'writes the specified modification time' do
    fake_writer = double('Writer').as_null_object

    expect(fake_writer).to receive(:write_local_file_header) { |**kwargs|
      expect(kwargs[:mtime]).to eq(Time.new('2018-01-01 00:00:00'))
    }.exactly(3).times

    described_class.open(StringIO.new, writer: fake_writer) do |zip|
      zip.write_stored_file('stored.txt', modification_time: Time.new('2018-01-01 00:00:00')) do |sink|
        sink << 'stored'
      end
      zip.write_deflated_file('deflated.txt', modification_time: Time.new('2018-01-01 00:00:00')) do |sink|
        sink << 'deflated'
      end
      zip.add_empty_directory(dirname: 'empty', modification_time: Time.new('2018-01-01 00:00:00'))
    end
  end
end
