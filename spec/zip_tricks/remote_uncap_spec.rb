require 'spec_helper'
require 'net/http'

describe ZipTricks::RemoteUncap do
  before :all do
    rack_app = File.expand_path(__dir__ + '/remote_uncap_rack_app.ru')
    # find a free tcp port
    tcpserver = TCPServer.new('127.0.0.1', 0)
    port = tcpserver.addr[1]
    addr = tcpserver.addr[3]
    tcpserver.close
    @server_addr = "#{addr}:#{port}"
    command = %W[bundle exec puma --bind tcp://#{@server_addr} #{rack_app}]
    server = IO.popen(command, 'r')
    @server_pid = server.pid
    # ensure server was sarted
    expect(@server_pid).not_to be_nil
    # wait for server to boot
    true while server.gets !~ /Ctrl-C/
  end

  after :all do
    begin
      Process.kill("TERM", @server_pid)
    rescue Errno::ESRCH
    end
    begin
      Process.wait(@server_pid)
    rescue Errno::ECHILD
    end
  end

  after :each do
    begin
      File.unlink('temp.zip')
    rescue Errno::ENOENT
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

    files = described_class.files_within_zip_at("http://#{@server_addr}/temp.zip")
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

    File.open('temp.zip', 'wb') do |f|
      ZipTricks::Streamer.open(f) do |zip|
        zip.add_stored_entry(filename: 'first-file-zero-size.bin',
                             size: payload1.size,
                             crc32: payload1_crc)
        zip.write_stored_file('second-file.bin') { |w| IO.copy_stream(payload2, w) }
      end
    end
    payload1.rewind
    payload2.rewind

    first, second = described_class.files_within_zip_at("http://#{@server_addr}/temp.zip")

    expect(first.filename).to eq('first-file-zero-size.bin')
    expect(first.compressed_size).to be_zero

    expect(second.filename).to eq('second-file.bin')
    expect(second.uncompressed_size).to eq(payload2.size)
    File.open('temp.zip', 'rb') do |source_zip|
      source_zip.seek(second.compressed_data_offset, IO::SEEK_SET)
      expect(source_zip.read(12)).to eq(payload2.read(12))
    end
  end
end
