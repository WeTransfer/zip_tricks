require_relative '../spec_helper'

describe ZipTricks::ZipWriter do
  class ByteReader < Struct.new(:io)
    def initialize(io)
      super(io).tap { io.rewind }
    end

    def read_1b
      read_n(1).unpack('C').first
    end

    def read_2b
      read_n(2).unpack('v').first
    end

    def read_2c
      read_n(2).unpack('CC').first
    end

    def read_4b
      read_n(4).unpack('V').first
    end

    def read_4b_signed
      read_n(4).unpack('l<').first
    end

    def read_8b
      read_n(8).unpack('Q<').first
    end

    def read_n(n)
      io.read(n).tap do |r|
        raise "Expected to read #{n} bytes, but read() returned nil" if r.nil?
        raise "Expected to read #{n} bytes, but read #{r.bytesize} instead" if r.bytesize != n
      end
    end

    # For conveniently going to a specific signature
    def seek_to_start_of_signature(signature)
      io.rewind
      signature_encoded = [signature].pack('V')
      idx = io.read.index(signature_encoded)
      raise "Could not find the signature #{signature} in the buffer" unless idx
      io.seek(idx, IO::SEEK_SET)
    end
  end

  describe '#write_local_file_header' do
    it 'writes the local file header for an entry that does not require Zip64' do
      buf = StringIO.new
      mtime = Time.utc(2016, 7, 17, 13, 48)

      subject = ZipTricks::ZipWriter.new
      subject.write_local_file_header(io: buf,
                                      gp_flags: 12,
                                      crc32: 456,
                                      compressed_size: 768,
                                      uncompressed_size: 901,
                                      mtime: mtime,
                                      filename: 'foo.bin',
                                      storage_mode: 8)

      br = ByteReader.new(buf)
      expect(br.read_4b).to eq(0x04034b50)   # Signature
      expect(br.read_2b).to eq(20)           # Version needed to extract
      expect(br.read_2b).to eq(12)           # gp flags
      expect(br.read_2b).to eq(8)            # storage mode
      expect(br.read_2b).to eq(28_160)        # DOS time
      expect(br.read_2b).to eq(18_673)        # DOS date
      expect(br.read_4b).to eq(456)          # CRC32
      expect(br.read_4b).to eq(768)          # compressed size
      expect(br.read_4b).to eq(901)          # uncompressed size
      expect(br.read_2b).to eq(7)            # filename size
      expect(br.read_2b).to eq(9)            # extra fields size

      expect(br.read_n(7)).to eq('foo.bin')  # extra fields size

      expect(br.read_2b).to eq(0x5455)       # Extended timestamp extra tag
      expect(br.read_2b).to eq(5)            # Size of the timestamp extra
      expect(br.read_1b).to eq(1)            # The timestamp flag, with only the lowest bit set

      ext_mtime = br.read_4b_signed
      expect(ext_mtime).to eq(1_468_763_280) # The mtime encoded as a 4byte uint

      parsed_time = Time.at(ext_mtime)
      expect(parsed_time.year).to eq(2_016)
    end

    it 'writes the local file header for an entry that does require Zip64 based \
        on uncompressed size (with the Zip64 extra)' do
      buf = StringIO.new
      mtime = Time.utc(2016, 7, 17, 13, 48)

      subject = ZipTricks::ZipWriter.new
      subject.write_local_file_header(io: buf,
                                      gp_flags: 12,
                                      crc32: 456,
                                      compressed_size: 768,
                                      uncompressed_size: 0xFFFFFFFF + 1,
                                      mtime: mtime,
                                      filename: 'foo.bin',
                                      storage_mode: 8)

      br = ByteReader.new(buf)
      expect(br.read_4b).to eq(0x04034b50)   # Signature
      expect(br.read_2b).to eq(45)           # Version needed to extract
      expect(br.read_2b).to eq(12)           # gp flags
      expect(br.read_2b).to eq(8)            # storage mode
      expect(br.read_2b).to eq(28_160)        # DOS time
      expect(br.read_2b).to eq(18_673)        # DOS date
      expect(br.read_4b).to eq(456)          # CRC32
      expect(br.read_4b).to eq(0xFFFFFFFF)   # compressed size
      expect(br.read_4b).to eq(0xFFFFFFFF)   # uncompressed size
      expect(br.read_2b).to eq(7)            # filename size
      expect(br.read_2b).to eq(29)           # extra fields size (Zip64 + extended timestamp)
      expect(br.read_n(7)).to eq('foo.bin')  # extra fields size

      expect(buf).not_to be_eof

      expect(br.read_2b).to eq(1)            # Zip64 extra tag
      expect(br.read_2b).to eq(16)           # Size of the Zip64 extra payload
      expect(br.read_8b).to eq(0xFFFFFFFF + 1) # uncompressed size
      expect(br.read_8b).to eq(768)          # compressed size
    end

    it 'writes the local file header for an entry that does require Zip64 based \
        on compressed size (with the Zip64 extra)' do
      buf = StringIO.new
      mtime = Time.utc(2016, 7, 17, 13, 48)

      subject = ZipTricks::ZipWriter.new
      subject.write_local_file_header(io: buf,
                                      gp_flags: 12,
                                      crc32: 456,
                                      compressed_size: 0xFFFFFFFF + 1,
                                      uncompressed_size: 768,
                                      mtime: mtime,
                                      filename: 'foo.bin',
                                      storage_mode: 8)

      br = ByteReader.new(buf)
      expect(br.read_4b).to eq(0x04034b50)   # Signature
      expect(br.read_2b).to eq(45)           # Version needed to extract
      expect(br.read_2b).to eq(12)           # gp flags
      expect(br.read_2b).to eq(8)            # storage mode
      expect(br.read_2b).to eq(28_160)       # DOS time
      expect(br.read_2b).to eq(18_673)       # DOS date
      expect(br.read_4b).to eq(456)          # CRC32
      expect(br.read_4b).to eq(0xFFFFFFFF)   # compressed size
      expect(br.read_4b).to eq(0xFFFFFFFF)   # uncompressed size
      expect(br.read_2b).to eq(7)            # filename size
      expect(br.read_2b).to eq(29)           # extra fields size
      expect(br.read_n(7)).to eq('foo.bin')  # extra fields size

      expect(buf).not_to be_eof

      expect(br.read_2b).to eq(1)            # Zip64 extra tag
      expect(br.read_2b).to eq(16)           # Size of the Zip64 extra payload
      expect(br.read_8b).to eq(768)          # uncompressed size
      expect(br.read_8b).to eq(0xFFFFFFFF + 1) # compressed size
    end
  end

  describe '#write_data_descriptor' do
    it 'writes 4-byte sizes into the data descriptor for standard file sizes' do
      buf = StringIO.new

      subject.write_data_descriptor(io: buf,
                                    crc32: 123,
                                    compressed_size: 89_821,
                                    uncompressed_size: 990_912)

      br = ByteReader.new(buf)
      expect(br.read_4b).to eq(0x08074b50)    # Signature
      expect(br.read_4b).to eq(123)           # CRC32
      expect(br.read_4b).to eq(89_821)        # compressed size
      expect(br.read_4b).to eq(990_912)       # uncompressed size
      expect(buf).to be_eof
    end

    it 'writes 8-byte sizes into the data descriptor for Zip64 compressed file size' do
      buf = StringIO.new

      subject.write_data_descriptor(io: buf,
                                    crc32: 123,
                                    compressed_size: 0xFFFFFFFF + 1,
                                    uncompressed_size: 990_912)

      br = ByteReader.new(buf)
      expect(br.read_4b).to eq(0x08074b50)        # Signature
      expect(br.read_4b).to eq(123)               # CRC32
      expect(br.read_8b).to eq(0xFFFFFFFF + 1)    # compressed size
      expect(br.read_8b).to eq(990_912)           # uncompressed size
      expect(buf).to be_eof
    end

    it 'writes 8-byte sizes into the data descriptor for Zip64 uncompressed file size' do
      buf = StringIO.new

      subject.write_data_descriptor(io: buf,
                                    crc32: 123,
                                    compressed_size: 123,
                                    uncompressed_size: 0xFFFFFFFF + 1)

      br = ByteReader.new(buf)
      expect(br.read_4b).to eq(0x08074b50)      # Signature
      expect(br.read_4b).to eq(123)             # CRC32
      expect(br.read_8b).to eq(123)             # compressed size
      expect(br.read_8b).to eq(0xFFFFFFFF + 1)  # uncompressed size
      expect(buf).to be_eof
    end
  end

  describe '#write_central_directory_file_header' do
    it 'writes the file header for a small-ish entry' do
      buf = StringIO.new

      subject.write_central_directory_file_header(io: buf,
                                                  local_file_header_location: 898_921,
                                                  gp_flags: 555,
                                                  storage_mode: 23,
                                                  compressed_size: 901,
                                                  uncompressed_size: 909_102,
                                                  mtime: Time.utc(2016, 2, 2, 14, 0),
                                                  crc32: 89_765,
                                                  filename: 'a-file.txt')

      br = ByteReader.new(buf)
      expect(br.read_4b).to eq(0x02014b50)      # Central directory entry sig
      expect(br.read_2b).to eq(820)             # version made by
      expect(br.read_2b).to eq(20)              # version need to extract
      expect(br.read_2b).to eq(555)             # general purpose bit flag (explicitly
      # set to bogus value to ensure we pass it through)
      expect(br.read_2b).to eq(23)              # compression method (explicitly set to bogus value)
      expect(br.read_2b).to eq(28_672)          # last mod file time
      expect(br.read_2b).to eq(18_498)          # last mod file date
      expect(br.read_4b).to eq(89_765)          # crc32
      expect(br.read_4b).to eq(901)             # compressed size
      expect(br.read_4b).to eq(909_102)         # uncompressed size
      expect(br.read_2b).to eq(10)              # filename length
      expect(br.read_2b).to eq(9)               # extra field length
      expect(br.read_2b).to eq(0)               # file comment
      expect(br.read_2b).to eq(0)               # disk number, must be blanked to the
      # maximum value because of The Unarchiver bug
      expect(br.read_2b).to eq(0)               # internal file attributes
      expect(br.read_4b).to eq(2_175_008_768)   # external file attributes
      expect(br.read_4b).to eq(898_921)         # relative offset of local header
      expect(br.read_n(10)).to eq('a-file.txt') # the filename
    end

    it 'writes the file header for an entry that contains an empty directory' do
      buf = StringIO.new

      subject.write_central_directory_file_header(io: buf,
                                                  local_file_header_location: 898_921,
                                                  gp_flags: 555,
                                                  storage_mode: 23,
                                                  compressed_size: 0,
                                                  uncompressed_size: 0,
                                                  mtime: Time.utc(2016, 2, 2, 14, 0),
                                                  crc32: 0,
                                                  filename: 'directory/')

      br = ByteReader.new(buf)
      expect(br.read_4b).to eq(0x02014b50)      # Central directory entry sig
      expect(br.read_2b).to eq(820)             # version made by
      expect(br.read_2b).to eq(20)              # version need to extract
      expect(br.read_2b).to eq(555)             # general purpose bit flag (explicitly
      # set to bogus value to ensure we pass it through)
      expect(br.read_2b).to eq(23)              # compression method (explicitly set to bogus value)
      expect(br.read_2b).to eq(28_672)          # last mod file time
      expect(br.read_2b).to eq(18_498)          # last mod file date
      expect(br.read_4b).to eq(0)               # crc32
      expect(br.read_4b).to eq(0)               # compressed size
      expect(br.read_4b).to eq(0)               # uncompressed size
      expect(br.read_2b).to eq(10)              # filename length
      expect(br.read_2b).to eq(9)               # extra field length
      expect(br.read_2b).to eq(0)               # file comment
      expect(br.read_2b).to eq(0)               # disk number, must be blanked to the
      # maximum value because of The Unarchiver bug
      expect(br.read_2b).to eq(0)               # internal file attributes
      expect(br.read_4b).to eq(1_106_051_072)   # external file attributes
      expect(br.read_4b).to eq(898_921)         # relative offset of local header
      expect(br.read_n(10)).to eq('directory/') # the filename
    end

    it 'writes the file header for an entry that requires Zip64 extra because of \
        the uncompressed size' do
      buf = StringIO.new

      subject.write_central_directory_file_header(io: buf,
                                                  local_file_header_location: 898_921,
                                                  gp_flags: 555,
                                                  storage_mode: 23,
                                                  compressed_size: 901,
                                                  uncompressed_size: 0xFFFFFFFFF + 3,
                                                  mtime: Time.utc(2016, 2, 2, 14, 0),
                                                  crc32: 89_765,
                                                  filename: 'a-file.txt')

      br = ByteReader.new(buf)
      expect(br.read_4b).to eq(0x02014b50)      # Central directory entry sig
      expect(br.read_2b).to eq(820)             # version made by
      expect(br.read_2b).to eq(45)              # version need to extract
      expect(br.read_2b).to eq(555)             # general purpose bit flag
      # (explicitly set to bogus value
      # to ensure we pass it through)
      expect(br.read_2b).to eq(23)              # compression method (explicitly
      # set to bogus value)
      expect(br.read_2b).to eq(28_672)          # last mod file time
      expect(br.read_2b).to eq(18_498)          # last mod file date
      expect(br.read_4b).to eq(89_765)          # crc32
      expect(br.read_4b).to eq(0xFFFFFFFF)      # compressed size
      expect(br.read_4b).to eq(0xFFFFFFFF)      # uncompressed size
      expect(br.read_2b).to eq(10)              # filename length
      expect(br.read_2b).to eq(41)              # extra field length
      expect(br.read_2b).to eq(0)               # file comment
      expect(br.read_2b).to eq(0xFFFF)          # disk number, must be blanked
      # to the maximum value because
      # of The Unarchiver bug
      expect(br.read_2b).to eq(0)               # internal file attributes
      expect(br.read_4b).to eq(2_175_008_768)   # external file attributes
      expect(br.read_4b).to eq(0xFFFFFFFF)      # relative offset of local header
      expect(br.read_n(10)).to eq('a-file.txt') # the filename

      expect(buf).not_to be_eof
      expect(br.read_2b).to eq(1)               # Zip64 extra tag
      expect(br.read_2b).to eq(28)              # Size of the Zip64 extra payload
      expect(br.read_8b).to eq(0xFFFFFFFFF + 3) # uncompressed size
      expect(br.read_8b).to eq(901)             # compressed size
      expect(br.read_8b).to eq(898_921)         # local file header location
    end

    it 'writes the file header for an entry that requires Zip64 extra because of \
        the compressed size' do
      buf = StringIO.new

      subject.write_central_directory_file_header(io: buf,
                                                  local_file_header_location: 898_921,
                                                  gp_flags: 555,
                                                  storage_mode: 23,
                                                  compressed_size: 0xFFFFFFFFF + 3,
                                                  # the worst compression scheme in the universe
                                                  uncompressed_size: 901,
                                                  mtime: Time.utc(2016, 2, 2, 14, 0),
                                                  crc32: 89_765,
                                                  filename: 'a-file.txt')

      br = ByteReader.new(buf)
      expect(br.read_4b).to eq(0x02014b50)      # Central directory entry sig
      expect(br.read_2b).to eq(820)             # version made by
      expect(br.read_2b).to eq(45)              # version need to extract
      expect(br.read_2b).to eq(555)             # general purpose bit flag (explicitly
      # set to bogus value to ensure we pass it through)
      expect(br.read_2b).to eq(23)              # compression method (explicitly set to bogus value)
      expect(br.read_2b).to eq(28_672)          # last mod file time
      expect(br.read_2b).to eq(18_498)          # last mod file date
      expect(br.read_4b).to eq(89_765)          # crc32
      expect(br.read_4b).to eq(0xFFFFFFFF)      # compressed size
      expect(br.read_4b).to eq(0xFFFFFFFF)      # uncompressed size
      expect(br.read_2b).to eq(10)              # filename length
      expect(br.read_2b).to eq(41)              # extra field length
      expect(br.read_2b).to eq(0)               # file comment
      expect(br.read_2b).to eq(0xFFFF)          # disk number, must be blanked to the
      # maximum value because of The Unarchiver bug
      expect(br.read_2b).to eq(0)               # internal file attributes
      expect(br.read_4b).to eq(2_175_008_768)   # external file attributes
      expect(br.read_4b).to eq(0xFFFFFFFF)      # relative offset of local header
      expect(br.read_n(10)).to eq('a-file.txt') # the filename

      expect(buf).not_to be_eof
      expect(br.read_2b).to eq(1)               # Zip64 extra tag
      expect(br.read_2b).to eq(28)              # Size of the Zip64 extra payload
      expect(br.read_8b).to eq(901)             # uncompressed size
      expect(br.read_8b).to eq(0xFFFFFFFFF + 3) # compressed size
      expect(br.read_8b).to eq(898_921)         # local file header location
    end

    it 'writes the file header for an entry that requires Zip64 extra because of \
        the local file header offset being beyound 4GB' do
      buf = StringIO.new

      subject.write_central_directory_file_header(io: buf,
                                                  local_file_header_location: 0xFFFFFFFFF + 1,
                                                  gp_flags: 555,
                                                  storage_mode: 23,
                                                  compressed_size: 8_981,
                                                  # the worst compression scheme in the universe
                                                  uncompressed_size: 819_891,
                                                  mtime: Time.utc(2016, 2, 2, 14, 0),
                                                  crc32: 89_765,
                                                  filename: 'a-file.txt')

      br = ByteReader.new(buf)
      expect(br.read_4b).to eq(0x02014b50)      # Central directory entry sig
      expect(br.read_2b).to eq(820)             # version made by
      expect(br.read_2b).to eq(45)              # version need to extract
      expect(br.read_2b).to eq(555)             # general purpose bit flag (explicitly
      # set to bogus value to ensure we pass it through)
      expect(br.read_2b).to eq(23)              # compression method (explicitly set to bogus value)
      expect(br.read_2b).to eq(28_672)          # last mod file time
      expect(br.read_2b).to eq(18_498)          # last mod file date
      expect(br.read_4b).to eq(89_765)          # crc32
      expect(br.read_4b).to eq(0xFFFFFFFF)      # compressed size
      expect(br.read_4b).to eq(0xFFFFFFFF)      # uncompressed size
      expect(br.read_2b).to eq(10)              # filename length
      expect(br.read_2b).to eq(41)              # extra field length
      expect(br.read_2b).to eq(0)               # file comment
      expect(br.read_2b).to eq(0xFFFF)          # disk number, must be blanked to the
      # maximum value because of The Unarchiver bug
      expect(br.read_2b).to eq(0)               # internal file attributes
      expect(br.read_4b).to eq(2_175_008_768)   # external file attributes
      expect(br.read_4b).to eq(0xFFFFFFFF)      # relative offset of local header
      expect(br.read_n(10)).to eq('a-file.txt') # the filename

      expect(buf).not_to be_eof
      expect(br.read_2b).to eq(1)               # Zip64 extra tag
      expect(br.read_2b).to eq(28)              # Size of the Zip64 extra payload
      expect(br.read_8b).to eq(819_891)         # uncompressed size
      expect(br.read_8b).to eq(8_981)           # compressed size
      expect(br.read_8b).to eq(0xFFFFFFFFF + 1) # local file header location
    end
  end

  describe '#write_end_of_central_directory' do
    it 'writes out the EOCD with all markers for a small ZIP file with just a few entries' do
      buf = StringIO.new

      num_files = rand(8..190)
      subject.write_end_of_central_directory(io: buf,
                                             start_of_central_directory_location: 9_091_211,
                                             central_directory_size: 9_091,
                                             num_files_in_archive: num_files)

      br = ByteReader.new(buf)
      expect(br.read_4b).to eq(0x06054b50) # EOCD signature
      expect(br.read_2b).to eq(0)         # number of this disk
      expect(br.read_2b).to eq(0)         # number of the disk with the EOCD record
      expect(br.read_2b).to eq(num_files) # number of files on this disk
      expect(br.read_2b).to eq(num_files) # number of files in central directory
      # total (for all disks)
      expect(br.read_4b).to eq(9_091) # size of the central directory (cdir records for all files)
      expect(br.read_4b).to eq(9_091_211) # start of central directory offset from
      # the beginning of file/disk

      comment_length = br.read_2b
      expect(comment_length).not_to be_zero

      expect(br.read_n(comment_length)).to match(/ZipTricks/)
    end

    it 'writes out the custom comment' do
      buf = ''
      comment = 'Ohai mate'
      subject.write_end_of_central_directory(io: buf,
                                             start_of_central_directory_location: 9_091_211,
                                             central_directory_size: 9_091,
                                             num_files_in_archive: 4,
                                             comment: comment)

      size_and_comment = buf[((comment.bytesize + 2) * -1)..-1]
      comment_size = size_and_comment.unpack('v')[0]
      expect(comment_size).to eq(comment.bytesize)
    end

    it 'writes out the Zip64 EOCD as well if the central directory is located \
        beyound 4GB in the archive' do
      buf = StringIO.new

      num_files = rand(8..190)
      subject.write_end_of_central_directory(io: buf,
                                             start_of_central_directory_location: 0xFFFFFFFF + 3,
                                             central_directory_size: 9091,
                                             num_files_in_archive: num_files)

      br = ByteReader.new(buf)

      expect(br.read_4b).to eq(0x06064b50)      # Zip64 EOCD signature
      expect(br.read_8b).to eq(44)              # Zip64 EOCD record size
      expect(br.read_2b).to eq(820)             # Version made by
      expect(br.read_2b).to eq(45)              # Version needed to extract
      expect(br.read_4b).to eq(0)               # Number of this disk
      expect(br.read_4b).to eq(0)               # Number of the disk with the Zip64 EOCD record
      expect(br.read_8b).to eq(num_files)       # Number of entries in the central
      # directory of this disk
      expect(br.read_8b).to eq(num_files)       # Number of entries in the central
      # directories of all disks
      expect(br.read_8b).to eq(9_091)           # Central directory size
      expect(br.read_8b).to eq(0xFFFFFFFF + 3)  # Start of central directory location

      expect(br.read_4b).to eq(0x07064b50)      # Zip64 EOCD locator signature
      expect(br.read_4b).to eq(0)               # Number of the disk with the EOCD locator signature
      expect(br.read_8b).to eq((0xFFFFFFFF + 3) + 9_091) # Where the Zip64 EOCD record starts
      expect(br.read_4b).to eq(1)           # Total number of disks

      # Then the usual EOCD record
      expect(br.read_4b).to eq(0x06054b50)  # EOCD signature
      expect(br.read_2b).to eq(0)           # number of this disk
      expect(br.read_2b).to eq(0)           # number of the disk with the EOCD record
      expect(br.read_2b).to eq(0xFFFF)      # number of files on this disk
      expect(br.read_2b).to eq(0xFFFF)      # number of files in central directory
      # total (for all disks)
      expect(br.read_4b).to eq(0xFFFFFFFF)  # size of the central directory
      # (cdir records for all files)
      expect(br.read_4b).to eq(0xFFFFFFFF)  # start of central directory offset
      # from the beginning of file/disk

      comment_length = br.read_2b
      expect(comment_length).not_to be_zero
      expect(br.read_n(comment_length)).to match(/ZipTricks/)
    end

    it 'writes out the Zip64 EOCD if the archive has more than 0xFFFF files' do
      buf = StringIO.new

      subject.write_end_of_central_directory(io: buf,
                                             start_of_central_directory_location: 123,
                                             central_directory_size: 9_091,
                                             num_files_in_archive: 0xFFFF + 1)

      br = ByteReader.new(buf)

      expect(br.read_4b).to eq(0x06064b50)      # Zip64 EOCD signature
      br.read_8b
      br.read_2b
      br.read_2b
      br.read_4b
      br.read_4b
      expect(br.read_8b).to eq(0xFFFF + 1)      # Number of entries in the central
      # directory of this disk
      expect(br.read_8b).to eq(0xFFFF + 1) # Number of entries in the central
      # directories of all disks
    end

    it 'writes out the Zip64 EOCD if the central directory size exceeds 0xFFFFFFFF' do
      buf = StringIO.new

      subject.write_end_of_central_directory(io: buf,
                                             start_of_central_directory_location: 123,
                                             central_directory_size: 0xFFFFFFFF + 2,
                                             num_files_in_archive: 5)

      br = ByteReader.new(buf)

      expect(br.read_4b).to eq(0x06064b50) # Zip64 EOCD signature
      br.read_8b
      br.read_2b
      br.read_2b
      br.read_4b
      br.read_4b
      expect(br.read_8b).to eq(5)       # Number of entries in the central directory of this disk
      expect(br.read_8b).to eq(5)       # Number of entries in the central directories of all disks
    end
  end
end
