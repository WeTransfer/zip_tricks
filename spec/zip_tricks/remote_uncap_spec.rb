require 'spec_helper'

describe ZipTricks::RemoteUncap, webmock: true do
  let(:uri) { URI.parse('http://example.com/file.zip') }

  after :each do
    begin
      File.unlink('temp.zip')
    rescue
      Errno::ENOENT
    end
  end

  it 'returns an array of remote entries that can be used to fetch the segments \
      from within the ZIP' do
    payload1 = Tempfile.new 'payload1'
    payload1 << Random.new.bytes((1024 * 1024 * 5) + 10)
    payload1.flush
    payload1.rewind

    payload2 = Tempfile.new 'payload2'
    payload2 << Random.new.bytes(1024 * 1024 * 3)
    payload2.flush
    payload2.rewind

    File.open('temp.zip', 'wb') do |f|
      ZipTricks::Streamer.open(f) do |zip|
        zip.write_stored_file('first-file.bin') { |w| IO.copy_stream(payload1, w) }
        zip.write_stored_file('second-file.bin') { |w| IO.copy_stream(payload2, w) }
      end
    end
    payload1.rewind
    payload2.rewind

    expect(File).to be_exist('temp.zip')

    allow_any_instance_of(described_class).to receive(:request_object_size) {
      File.size('temp.zip')
    }
    allow_any_instance_of(described_class).to receive(:request_range) { |_instance, range|
      File.open('temp.zip', 'rb') do |f|
        f.seek(range.begin)
        f.read(range.end - range.begin + 1)
      end
    }

    payload1.rewind
    payload2.rewind

    files = described_class.files_within_zip_at('http://fake.example.com')
    expect(files).to be_kind_of(Array)
    expect(files.length).to eq(2)

    first, second = *files

    expect(first.filename).to eq('first-file.bin')
    expect(first.uncompressed_size).to eq(payload1.size)
    File.open('temp.zip', 'rb') do |readback|
      readback.seek(first.compressed_data_offset, IO::SEEK_SET)
      expect(readback.read(12)).to eq(payload1.read(12))
    end

    expect(second.filename).to eq('second-file.bin')
    expect(second.uncompressed_size).to eq(payload2.size)
    File.open('temp.zip', 'rb') do |readback|
      readback.seek(second.compressed_data_offset, IO::SEEK_SET)
      expect(readback.read(12)).to eq(payload2.read(12))
    end
  end

  it 'can cope with an empty file within the zip' do
    payload1 = Tempfile.new 'payload1'
    payload1.flush
    payload1.rewind

    payload2 = Tempfile.new 'payload2'
    payload2 << Random.new.bytes(1024)
    payload2.flush
    payload2.rewind

    payload1_crc = Zlib.crc32(payload1.read).tap { payload1.rewind }
    # Rubocop: warning: Useless assignment to variable - payload2_crc.
    payload2_crc = Zlib.crc32(payload2.read).tap { payload2.rewind }

    readable_zip = Tempfile.new 'somezip'
    ZipTricks::Streamer.open(readable_zip) do |zip|
      zip.add_stored_entry(filename: 'first-file-zero-size.bin',
                           size: payload1.size,
                           crc32: payload1_crc)
      zip.write_stored_file('second-file.bin') { |w| IO.copy_stream(payload2, w) }
    end
    readable_zip.flush
    readable_zip.rewind

    allow_any_instance_of(described_class).to receive(:request_object_size) {
      readable_zip.size
    }
    allow_any_instance_of(described_class).to receive(:request_range) { |_instance, range|
      readable_zip.seek(range.begin, IO::SEEK_SET)
      readable_zip.read(range.end - range.begin + 1)
    }

    payload1.rewind
    payload2.rewind

    first, second = described_class.files_within_zip_at('http://fake.example.com')

    expect(first.filename).to eq('first-file-zero-size.bin')
    expect(first.compressed_size).to be_zero

    expect(second.filename).to eq('second-file.bin')
    expect(second.uncompressed_size).to eq(payload2.size)
    readable_zip.seek(second.compressed_data_offset, IO::SEEK_SET)
    expect(readable_zip.read(12)).to eq(payload2.read(12))
  end
end
