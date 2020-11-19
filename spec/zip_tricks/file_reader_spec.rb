require 'spec_helper'
describe ZipTricks::FileReader do
  context 'with a file without EOCD' do
    it 'raises the MissingEOCD exception and refuses to read' do
      f = StringIO.new
      10.times { f << ('A' * 1_024) }
      f.rewind

      expect { described_class.read_zip_structure(io: f) }.to raise_error(described_class::MissingEOCD)
    end
  end

  describe 'read_zip_straight_ahead' do
    it 'returns all the entries it can recover' do
      zipfile = StringIO.new
      war_and_peace = File.binread(__dir__ + '/war-and-peace.txt')
      ZipTricks::Streamer.open(zipfile) do |zip|
        zip.add_stored_entry filename: 'text1.txt',
                             crc32: Zlib.crc32(war_and_peace),
                             size: war_and_peace.bytesize
        zip << war_and_peace
        zip.add_stored_entry filename: 'text2.txt',
                             crc32: Zlib.crc32(war_and_peace),
                             size: war_and_peace.bytesize
        zip << war_and_peace
        zip.add_stored_entry filename: 'text3.txt',
                             crc32: Zlib.crc32(war_and_peace),
                             size: war_and_peace.bytesize
        zip << war_and_peace
      end
      zipfile.rewind

      recovered_entries = described_class.read_zip_straight_ahead(io: zipfile)
      expect(recovered_entries.length).to eq(3)
      recovered_entries.each do |entry|
        expect(entry.storage_mode).to eq(0)
        expect(entry.compressed_size).to eq(496_006)
        expect(entry.uncompressed_size).to eq(496_006)
      end

      first, second, third = recovered_entries
      expect(first.compressed_data_offset).to eq(48)
      expect(second.compressed_data_offset).to eq(496_102)
      expect(third.compressed_data_offset).to eq(992_156)

      recovered_entries.each do |entry|
        zipfile.seek(entry.compressed_data_offset)
        expect(zipfile.read(5)).to eq(war_and_peace[0...5])
      end
    end

    it 'recovers an entry that uses Zip64 extra fields' do
      zipfile = StringIO.new
      w = ZipTricks::ZipWriter.new
      w.write_local_file_header(io: zipfile,
                                filename: 'big.bin',
                                compressed_size: 0xFFFFFFFFFF,
                                uncompressed_size: 0xFFFFFFFFF,
                                crc32: 0,
                                gp_flags: 0,
                                mtime: Time.now,
                                storage_mode: 0)
      zipfile.rewind
      recovered_entries = described_class.read_zip_straight_ahead(io: zipfile)
      expect(recovered_entries.length).to eq(1)
      entry = recovered_entries.shift
      expect(entry.compressed_size).to eq(0xFFFFFFFFFF)
    end

    it 'raises when an entry uses a data descriptor' do
      zipfile = StringIO.new
      ZipTricks::Streamer.open(zipfile) do |zip|
        zip.write_deflated_file('war-and-peace.txt') do |sink|
          sink << File.read(__dir__ + '/war-and-peace.txt')
        end
      end
      zipfile.rewind

      expect { described_class.read_zip_straight_ahead(io: zipfile) }.to raise_error(described_class::UnsupportedFeature)
    end
  end

  context 'with a ZIP file where the size of the central directory is recorded incorrectly, and has a wrong value' do
    it 'is still able to read the entries' do
      # Purposefully create a ZIP that we will damage after
      zipfile = StringIO.new
      tolstoy = File.read(__dir__ + '/war-and-peace.txt')
      tolstoy.force_encoding(Encoding::BINARY)

      # Make a one-off Writer that corrupts the size of the central directory
      # and says there is more data in it than there actually is
      class EvilWriter < ZipTricks::ZipWriter
        def write_end_of_central_directory(**kwargs)
          # Pretend there has to be more data
          kwargs[:central_directory_size] = kwargs[:central_directory_size] + 64
          super(**kwargs)
        end
      end

      ZipTricks::Streamer.open(zipfile, writer: EvilWriter.new) do |zip|
        zip.write_deflated_file('text-1.txt') { |sink| sink << tolstoy }
        zip.write_deflated_file('text-2.txt') { |sink| sink << tolstoy }
      end

      # Find the start of the EOCD record (signature, then the information
      # about disk numbers and the information about the file counts
      eocd_start_marker = [0x06054b50, 0, 0, 2, 2].pack('Vvvvv')
      eocd_offset = zipfile.string.index(eocd_start_marker)
      expect(eocd_offset).not_to be_nil

      # Seek to the offset where the central directory size is going to be
      # (just after the string we looked for)
      zipfile.seek(eocd_offset + eocd_start_marker.bytesize)
      # and overwrite it.
      zipfile.write([118].pack('V'))
      zipfile.rewind

      entries = ZipTricks::FileReader.read_zip_structure(io: zipfile)

      expect(entries.length).to eq(2)
    end
  end

  context 'with an end-to-end ZIP file to read' do
    it 'reads and uncompresses the file written deflated with data descriptors' do
      zipfile = StringIO.new
      tolstoy = File.read(__dir__ + '/war-and-peace.txt')
      tolstoy.force_encoding(Encoding::BINARY)

      ZipTricks::Streamer.open(zipfile) do |zip|
        zip.write_deflated_file('war-and-peace.txt') do |sink|
          sink << tolstoy
        end
      end

      entries = described_class.read_zip_structure(io: zipfile)
      expect(entries.length).to eq(1)

      entry = entries.first

      readback = ''
      reader = entry.extractor_from(zipfile)
      readback << reader.extract(10) until reader.eof?

      expect(readback.bytesize).to eq(tolstoy.bytesize)
      expect(readback[0..10]).to eq(tolstoy[0..10])
      expect(readback[-10..-1]).to eq(tolstoy[-10..-1])
    end

    it 'performs local file header reads by default' do
      zipfile = StringIO.new
      tolstoy = File.read(__dir__ + '/war-and-peace.txt')
      tolstoy.force_encoding(Encoding::BINARY)

      ZipTricks::Streamer.open(zipfile) do |zip|
        40.times do |i|
          zip.write_deflated_file(format('war-and-peace-%d.txt', i)) { |sink| sink << tolstoy }
        end
      end
      zipfile.rewind

      read_monitor = ReadMonitor.new(zipfile)
      _entries = described_class.read_zip_structure(io: read_monitor, read_local_headers: true)
      expect(read_monitor.num_reads).to eq(44)
    end

    it 'performs local file header reads when `read_local_headers` is set to true' do
      zipfile = StringIO.new
      tolstoy = File.read(__dir__ + '/war-and-peace.txt')
      tolstoy.force_encoding(Encoding::BINARY)

      ZipTricks::Streamer.open(zipfile) do |zip|
        40.times do |i|
          zip.write_deflated_file(format('war-and-peace-%d.txt', i)) { |sink| sink << tolstoy }
        end
      end
      zipfile.rewind

      read_monitor = ReadMonitor.new(zipfile)
      entries = described_class.read_zip_structure(io: read_monitor, read_local_headers: true)
      expect(read_monitor.num_reads).to eq(44)

      expect(entries.length).to eq(40)
      entry = entries.first
      expect(entry).to be_known_offset
    end

    it 'performs a limited number of reads when `read_local_headers` is set to false' do
      zipfile = StringIO.new
      tolstoy = File.read(__dir__ + '/war-and-peace.txt')
      tolstoy.force_encoding(Encoding::BINARY)

      ZipTricks::Streamer.open(zipfile) do |zip|
        40.times do |i|
          zip.write_deflated_file(format('war-and-peace-%d.txt', i)) { |sink| sink << tolstoy }
        end
      end
      zipfile.rewind
      read_monitor = ReadMonitor.new(zipfile)

      entries = described_class.read_zip_structure(io: read_monitor, read_local_headers: false)

      expect(read_monitor.num_reads).to eq(4)
      expect(entries.length).to eq(40)
      entry = entries.first
      expect(entry).not_to be_known_offset
      expect { entry.compressed_data_offset }.to raise_error(/read/)
    end

    it 'reads the file written stored with data descriptors' do
      zipfile = StringIO.new
      tolstoy = File.binread(__dir__ + '/war-and-peace.txt')
      ZipTricks::Streamer.open(zipfile) do |zip|
        zip.write_stored_file('war-and-peace.txt') do |sink|
          sink << tolstoy
        end
      end

      entries = described_class.read_zip_structure(io: zipfile)
      expect(entries.length).to eq(1)

      entry = entries.first

      readback = entry.extractor_from(zipfile).extract
      expect(readback.bytesize).to eq(tolstoy.bytesize)
      expect(readback[0..10]).to eq(tolstoy[0..10])
    end
  end

  describe '#get_compressed_data_offset' do
    it 'reads the offset for an entry having Zip64 extra fields' do
      w = ZipTricks::ZipWriter.new
      out = StringIO.new
      out << Random.new.bytes(7_656_177)
      w.write_local_file_header(io: out,
                                filename: 'some file',
                                compressed_size: 0xFFFFFFFF + 5,
                                uncompressed_size: 0xFFFFFFFFF,
                                crc32: 123,
                                gp_flags: 4,
                                mtime: Time.now,
                                storage_mode: 8)

      out.rewind

      compressed_data_offset = subject.get_compressed_data_offset(io: out,
                                                                  local_file_header_offset: 7_656_177)
      expect(compressed_data_offset).to eq(7_656_245)
    end

    it 'reads the offset for an entry having a long name' do
      w = ZipTricks::ZipWriter.new
      out = StringIO.new
      out << Random.new.bytes(7)
      w.write_local_file_header(io: out,
                                filename: 'This is a file with a ridiculously long name.doc',
                                compressed_size: 10,
                                uncompressed_size: 15,
                                crc32: 123,
                                gp_flags: 4,
                                mtime: Time.now,
                                storage_mode: 8)

      out.rewind

      compressed_data_offset = subject.get_compressed_data_offset(io: out,
                                                                  local_file_header_offset: 7)
      expect(compressed_data_offset).to eq(94)
    end
  end

  it 'is able to latch to the EOCD location even if the signature for the EOCD record appears all over the ZIP' do
    # A VERY evil ZIP file which has this signature all over
    eocd_sig = [0x06054b50].pack('V')
    evil_str = "#{eocd_sig} and #{eocd_sig}"

    z = StringIO.new
    w = ZipTricks::ZipWriter.new
    w.write_local_file_header(io: z,
                              filename: evil_str,
                              compressed_size: evil_str.bytesize,
                              uncompressed_size: evil_str.bytesize,
                              crc32: 0x06054b50,
                              gp_flags: 0,
                              mtime: Time.now,
                              storage_mode: 0)
    z << evil_str
    where = z.tell
    w.write_central_directory_file_header(io: z,
                                          local_file_header_location: 0,
                                          gp_flags: 0,
                                          storage_mode: 0,
                                          filename: evil_str,
                                          compressed_size: evil_str.bytesize,
                                          uncompressed_size: evil_str.bytesize,
                                          mtime: Time.now,
                                          crc32: 0x06054b50)
    w.write_end_of_central_directory(io: z,
                                     start_of_central_directory_location: where,
                                     central_directory_size: z.tell - where,
                                     num_files_in_archive: 1,
                                     comment: evil_str)

    z.rewind
    entries = described_class.read_zip_structure(io: z)
    expect(entries.length).to eq(1)
  end

  it 'can handle a Zip64 central directory fields that only contains the required fields (substitutes for standard fields)' do
    # In this example central directory, 2 entries contain Zip64 extra where
    # only the local header offset is set (8 bytes each)
    # This is the exceptional case where we have to poke at a private method directly
    File.open(__dir__ + '/cdir_entry_with_partial_use_of_zip64_extra_fields.bin', 'rb') do |f|
      reader = described_class.new
      entry = reader.send(:read_cdir_entry, f)
      expect(entry.local_file_header_offset).to eq(4_312_401_349)
      expect(entry.filename).to eq('Motorhead - Ace Of Spades.srt')
      expect(entry.compressed_size).to eq(69_121)
      expect(entry.uncompressed_size).to eq(69_121)
    end
  end
end
