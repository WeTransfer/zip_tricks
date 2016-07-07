require 'spec_helper'

describe ZipTricks::RemoteUncap, webmock: true do
  let(:uri) { URI.parse('http://example.com/file.zip') }

  after :each do
    File.unlink('temp.zip') rescue Errno::ENOENT
  end

  it 'returns an array of remote entries that can be used to fetch the segments from within the ZIP' do
    payload1 = Tempfile.new 'payload1'
    payload1 << Random.new.bytes((1024 * 1024 * 5) + 10)
    payload1.flush; payload1.rewind;

    payload2 = Tempfile.new 'payload2'
    payload2 << Random.new.bytes(1024 * 1024 * 3)
    payload2.flush; payload2.rewind

    payload1_crc = Zlib.crc32(payload1.read).tap { payload1.rewind }
    payload2_crc = Zlib.crc32(payload2.read).tap { payload2.rewind }

    File.open('temp.zip', 'wb') do |f|
      ZipTricks::Streamer.open(f) do | zip |
        zip.add_stored_entry('first-file.bin', payload1.size, payload1_crc)
        while blob = payload1.read(1024 * 5)
          zip << blob
        end
        zip.add_stored_entry('second-file.bin', payload2.size, payload2_crc)
        while blob = payload2.read(1024 * 5)
          zip << blob
        end
      end
    end
    payload1.rewind; payload2.rewind

    expect(File).to be_exist('temp.zip')

    allow_any_instance_of(described_class).to receive(:request_object_size) {
      File.size('temp.zip')
    }
    allow_any_instance_of(described_class).to receive(:request_range) {|_instance, range|
      File.open('temp.zip', 'rb') do |f|
        f.seek(range.begin)
        f.read(range.end - range.begin + 1)
      end
    }

    payload1.rewind; payload2.rewind

    files = described_class.files_within_zip_at('http://fake.example.com')
    expect(files).to be_kind_of(Array)
    expect(files.length).to eq(2)

    first, second = *files

    expect(first.name).to eq('first-file.bin')
    expect(first.size_uncompressed).to eq(payload1.size)
    File.open('temp.zip', 'rb') do |readback|
      readback.seek(first.starts_at_offset, IO::SEEK_SET)
      expect(readback.read(12)).to eq(payload1.read(12))
    end

    expect(second.name).to eq('second-file.bin')
    expect(second.size_uncompressed).to eq(payload2.size)
    File.open('temp.zip', 'rb') do |readback|
      readback.seek(second.starts_at_offset, IO::SEEK_SET)
      expect(readback.read(12)).to eq(payload2.read(12))
    end
  end

  it 'can cope with an empty file within the zip' do
    payload1 = Tempfile.new 'payload1'
    payload1.flush; payload1.rewind;

    payload2 = Tempfile.new 'payload2'
    payload2 << Random.new.bytes(1024)
    payload2.flush; payload2.rewind

    payload1_crc = Zlib.crc32(payload1.read).tap { payload1.rewind }
    payload2_crc = Zlib.crc32(payload2.read).tap { payload2.rewind }

    File.open('temp.zip', 'wb') do |f|
      ZipTricks::Streamer.open(f) do | zip |
        zip.add_stored_entry('first-file.bin', payload1.size, payload1_crc)
        zip << '' # It is empty, so a read() would return nil
        zip.add_stored_entry('second-file.bin', payload2.size, payload2_crc)
        while blob = payload2.read(1024 * 5)
          zip << blob
        end
      end
    end
    payload1.rewind; payload2.rewind

    expect(File).to be_exist('temp.zip')

    allow_any_instance_of(described_class).to receive(:request_object_size) {
      File.size('temp.zip')
    }
    allow_any_instance_of(described_class).to receive(:request_range) {|_instance, range|
      File.open('temp.zip', 'rb') do |f|
        f.seek(range.begin)
        f.read(range.end - range.begin + 1)
      end
    }

    payload1.rewind; payload2.rewind

    files = described_class.files_within_zip_at('http://fake.example.com')
    expect(files).to be_kind_of(Array)
    expect(files.length).to eq(2)

    first, second = *files

    expect(first.name).to eq('first-file.bin')
    expect(first.size_uncompressed).to eq(payload1.size)
    File.open('temp.zip', 'rb') do |readback|
      readback.seek(first.starts_at_offset, IO::SEEK_SET)
      expect(readback.read(0)).to eq(payload1.read(0))
    end

    expect(second.name).to eq('second-file.bin')
    expect(second.size_uncompressed).to eq(payload2.size)
    File.open('temp.zip', 'rb') do |readback|
      readback.seek(second.starts_at_offset, IO::SEEK_SET)
      expect(readback.read(12)).to eq(payload2.read(12))
    end
  end
end
