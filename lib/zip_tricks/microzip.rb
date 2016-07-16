# A replacement for RubyZip for streaming, with a couple of small differences.
# The first difference is that it is verbosely-written-to-the-spec and you can actually
# follow what is happening. It does not support quite a few fancy features of Rubyzip,
# but instead it can be digested in one reading, and has solid Zip64 support. It also does
# not attempt any tricks with Zip64 placeholder extra fields because the ZipTricks streaming
# engine assumes you _know_ how large your file is (both compressed and uncompressed) _and_
# you have the file's CRC32 checksum upfront.
#
# Just like Rubyzip it will switch to Zip64 automatically if required, but there is no global
# setting to enable that behavior - it is always on.
class ZipTricks::Microzip
  STORED   = 0
  DEFLATED = 8

  TooMuch = Class.new(StandardError)
  DuplicateFilenames = Class.new(StandardError)
  UnknownMode = Class.new(StandardError)
  
  FOUR_BYTE_MAX_UINT = 0xFFFFFFFF
  TWO_BYTE_MAX_UINT = 0xFFFF

  VERSION_MADE_BY                        = 52
  VERSION_NEEDED_TO_EXTRACT              = 20
  VERSION_NEEDED_TO_EXTRACT_ZIP64        = 45

  C_V = 'V'.freeze
  C_v = 'v'.freeze
  C_Qe = 'Q<'.freeze

  class Entry < Struct.new(:filename, :crc32, :compressed_size, :uncompressed_size, :storage_mode, :mtime)
    def initialize(*)
      super
      @requires_zip64 = (compressed_size > FOUR_BYTE_MAX_UINT || uncompressed_size > FOUR_BYTE_MAX_UINT)
      @local_file_header_location = :LOCAL_FILE_HEADER_NOT_WRITTEN_YET
    end

    def requires_zip64?
      @requires_zip64
    end

    # Set the general purpose flags for the entry. The only flag we care about is the EFS
    # bit (bit 11) which should be set if the filename is UTF8. If it is, we need to set the
    # bit so that the unarchiving application knows that the filename in the archive is UTF-8
    # encoded, and not some DOS default. For ASCII entries it does not matter.
    def gp_flags_based_on_filename
      filename.encode(Encoding::ASCII)
      0b00000000000
    rescue Encoding::UndefinedConversionError # UTF8 filename
      # notify the unarchiver that the filename is in UTF8
      0b00000000000 | 0b100000000000
    end

    def write_local_file_header(io)
      io << [0x04034b50].pack(C_V)                        # local file header signature     4 bytes  (0x04034b50)

      if @requires_zip64                                  # version needed to extract       2 bytes
        io << [VERSION_NEEDED_TO_EXTRACT_ZIP64].pack(C_v)
      else
        io << [VERSION_NEEDED_TO_EXTRACT].pack(C_v)
      end

      io << [gp_flags_based_on_filename].pack("v")        # general purpose bit flag        2 bytes
      io << [storage_mode].pack("v")                      # compression method              2 bytes
      io << [to_binary_dos_time(mtime)].pack(C_v)         # last mod file time              2 bytes
      io << [to_binary_dos_date(mtime)].pack(C_v)         # last mod file date              2 bytes
      io << [crc32].pack(C_V)                             # crc-32                          4 bytes

      if @requires_zip64
        io << [FOUR_BYTE_MAX_UINT].pack(C_V)              # compressed size              4 bytes
        io << [FOUR_BYTE_MAX_UINT].pack(C_V)              # uncompressed size            4 bytes
      else
        io << [compressed_size].pack(C_V)                 # compressed size              4 bytes
        io << [uncompressed_size].pack(C_V)               # uncompressed size            4 bytes
      end

      # Filename should not be longer than 0xFFFF otherwise this wont fit here
      io << [filename.bytesize].pack(C_v)                 # file name length             2 bytes

      if @requires_zip64
        tmp = ''.force_encoding(Encoding::BINARY)
        write_zip_64_extra_for_local_file_header(tmp)
        io << [tmp.bytesize].pack(C_v)                    # extra field length              2 bytes
      else
        io << [0].pack(C_v)                               # extra field length              2 bytes
      end

      io << filename                                      # file name (variable size)

      write_zip_64_extra_for_local_file_header(io) if @requires_zip64
    end

    def write_zip_64_extra_for_local_file_header(io)
      io << [0x0001].pack(C_v)                        # 2 bytes    Tag for this "extra" block type
      io << [16].pack(C_v)                            # 2 bytes    Size of this "extra" block. For us it will always be 16 (2x8)
      io << [uncompressed_size].pack(C_Qe)            # 8 bytes    Original uncompressed file size
      io << [compressed_size].pack(C_Qe)              # 8 bytes    Size of compressed data
    end

    def write_zip_64_extra_for_central_directory_file_header(io)
      io << [0x0001].pack(C_v)                        # 2 bytes    Tag for this "extra" block type
      io << [28].pack(C_v)                            # 2 bytes    Size of this "extra" block. For us it will always be 28
      io << [uncompressed_size].pack(C_Qe)            # 8 bytes    Original uncompressed file size
      io << [compressed_size].pack(C_Qe)              # 8 bytes    Size of compressed data
      io << [@local_file_header_location].pack(C_Qe)  # 8 bytes    Offset of local header record
      io << [0].pack(C_V)                             # 4 bytes    Number of the disk on which this file starts
    end

=begin
    # I am keeping this for future use (if we want to generate ZIPs with postfix CRCs for instance)
    def write_data_descriptor(io)
      # 4.3.9.3 Although not originally assigned a signature, the value
      #       0x08074b50 has commonly been adopted as a signature value
      #       for the data descriptor record.
      # 4.3.9.4 When writing ZIP files, implementors SHOULD include the
      #    signature value marking the data descriptor record.  When
      #    the signature is used, the fields currently defined for
      #    the data descriptor record will immediately follow the
      #    signature.
      io << [0x08074b50].pack(C_V)
      # 4.3.9.2 When compressing files, compressed and uncompressed sizes
      # should be stored in ZIP64 format (as 8 byte values) when a
      # file's size exceeds 0xFFFFFFFF.   However ZIP64 format may be
      # used regardless of the size of a file.  When extracting, if
      # the zip64 extended information extra field is present for
      # the file the compressed and uncompressed sizes will be 8
      # byte values.
      io << [crc32].pack(C_V)                             # crc-32                          4 bytes
      if @requires_zip64
        io << [compressed_size].pack(C_Qe)                # compressed size                 8 bytes for ZIP64
        io << [uncompressed_size].pack(C_Qe)              # uncompressed size               8 bytes for ZIP64
      else
        io << [compressed_size].pack(C_V)                 # compressed size                 4 bytes
        io << [uncompressed_size].pack(C_V)               # uncompressed size               4 bytes
      end
    end
=end

    def write_central_directory_file_header(io, local_file_header_location)
      # At this point if the header begins somewhere beyound 0xFFFFFFFF we _have_ to record the offset
      # of the local file header as a zip64 extra field, so we give up, give in, you loose, love will always win...
      @requires_zip64 = true if local_file_header_location > FOUR_BYTE_MAX_UINT
      
      io << [0x02014b50].pack(C_V)                        # central file header signature   4 bytes  (0x02014b50)
      io << [VERSION_MADE_BY].pack(C_v)                   # version made by                 2 bytes
      if @requires_zip64
        io << [VERSION_NEEDED_TO_EXTRACT_ZIP64].pack(C_v) # version needed to extract       2 bytes
      else
        io << [VERSION_NEEDED_TO_EXTRACT].pack(C_v)       # version needed to extract       2 bytes
      end

      io << [gp_flags_based_on_filename].pack(C_v)        # general purpose bit flag        2 bytes
      io << [storage_mode].pack(C_v)                      # compression method              2 bytes
      io << [to_binary_dos_time(mtime)].pack(C_v)         # last mod file time              2 bytes
      io << [to_binary_dos_date(mtime)].pack(C_v)         # last mod file date              2 bytes
      io << [crc32].pack(C_V)                             # crc-32                          4 bytes

      if @requires_zip64
        io << [FOUR_BYTE_MAX_UINT].pack(C_V)              # compressed size              4 bytes
        io << [FOUR_BYTE_MAX_UINT].pack(C_V)              # uncompressed size            4 bytes
      else
        io << [compressed_size].pack(C_V)                 # compressed size              4 bytes
        io << [uncompressed_size].pack(C_V)               # uncompressed size            4 bytes
      end

      # Filename should not be longer than 0xFFFF otherwise this wont fit here
      io << [filename.bytesize].pack(C_v)                 # file name length                2 bytes

      if @requires_zip64
        local_fh_extra = ''.force_encoding(Encoding::BINARY)
        write_zip_64_extra_for_central_directory_file_header(local_fh_extra, local_file_header_location)
        io << [local_fh_extra.bytesize].pack(C_v)         # extra field length              2 bytes
      else
        io << [0].pack(C_v)                                 # extra field length              2 bytes
      end

      io << [0].pack(C_v)                                 # file comment length             2 bytes
      io << [0].pack(C_v)                                 # disk number start               2 bytes
      io << [0].pack(C_v)                                 # internal file attributes        2 bytes
      io << [0].pack(C_V)                                 # external file attributes        4 bytes

      if @requires_zip64
        io << [FOUR_BYTE_MAX_UINT].pack(C_V)              # relative offset of local header 4 bytes
      else
        io << [local_file_header_location].pack(C_V)     # relative offset of local header 4 bytes
      end
      io << filename                                      # file name (variable size)

      if @requires_zip64                                  # extra field (variable size)
        write_zip_64_extra_for_central_directory_file_header(io, local_file_header_location)
      end
                                                          # file comment (variable size)
    end

    private

    def to_binary_dos_time(t)
      (t.sec/2) + (t.min << 5) + (t.hour << 11)
    end

    def to_binary_dos_date(t)
      (t.day) + (t.month << 5) + ((t.year - 1980) << 9)
    end
  end

  # Creates a new streaming writer. The writer is stateful and knows it's list of ZIP file entries
  # as they are being added.
  # @param out_io[#<<, #tell] a writable object that responds to << and tell
  def initialize(out_io)
    @io = out_io
    @files = []
    @local_header_offsets = []
  end

  # Adds a file to the entry list and immediately writes out it's local file header into the
  # output stream.
  #
  # @param filename[String] The name of the file
  # @param crc32[Fixnum]    The CRC32 checksum of the file
  # @param compressed_size[Fixnum]    The size of the compressed (or stored) data - how much space it uses in the ZIP
  # @param uncompressed_size[Fixnum]  The size of the file once extracted
  # @param storage_mode[Fixnum]  Either 0 for "stored" or 8 for "deflated"
  # @param mtime[Time] What modification time to record for the file
  # @return [void]
  def add_local_file_header(filename:, crc32:, compressed_size:, uncompressed_size:, storage_mode:, mtime: Time.now.utc)
    if @files.any?{|e| e.filename == filename }
      raise DuplicateFilenames, "Filename #{filename.inspect} already used in the archive"
    end
    raise UnknownMode, "Unknown compression mode #{storage_mode}" unless [STORED, DEFLATED].include?(storage_mode)
    e = Entry.new(filename, crc32, compressed_size, uncompressed_size, storage_mode, mtime)
    @files << e
    @local_header_offsets << @io.tell
    e.write_local_file_header(@io)
  end

=begin
  # Keeping for future use (if we want to write postfix CRCs for instance).
  # The BOMArchiveHelper thing however is _really_ unhappy about those descriptors,
  # and is likely to error out if you feed it one.
  def write_data_descriptor
    last_file = @files[-1]
    raise "No files registered" unless last_file
    last_file.write_data_descriptor(@io)
  end
=end

  # Writes the central directory (including the Zip6 salient bits if necessary)
  #
  # @return [void]
  def write_central_directory
    start_of_central_directory = @io.tell

    # Central directory file headers, per file in order
    @files.zip(@local_header_offsets).each do |(file, offset)|
      file.write_central_directory_file_header(@io, offset)
    end
    central_dir_size = @io.tell - start_of_central_directory

    zip64_required = central_dir_size > FOUR_BYTE_MAX_UINT ||
      start_of_central_directory > FOUR_BYTE_MAX_UINT ||
      @files.length > TWO_BYTE_MAX_UINT ||
      @files.any?(&:requires_zip64?)

    # Then, if zip64 is used
    if zip64_required
      # [zip64 end of central directory record]
      zip64_eocdr_offset = @io.tell
                                                # zip64 end of central dir
      @io << [0x06064b50].pack(C_V)             # signature                       4 bytes  (0x06064b50)
      @io << [44].pack(C_Qe)                    # size of zip64 end of central
                                                # directory record                8 bytes
                                                # (this is ex. the 12 bytes of the signature and the size value itself).
                                                # Without the extensible data sector it is always 44.
      @io << [VERSION_MADE_BY].pack(C_v)                      # version made by                 2 bytes
      @io << [VERSION_NEEDED_TO_EXTRACT_ZIP64].pack(C_v)      # version needed to extract       2 bytes
      @io << [0].pack(C_V)                                    # number of this disk             4 bytes
      @io << [0].pack(C_V)                                    # number of the disk with the
      @io                                                     # start of the central directory  4 bytes
      @io << [@files.length].pack(C_Qe)                       # total number of entries in the
      @io                                                     # central directory on this disk  8 bytes
      @io << [@files.length].pack(C_Qe)                       # total number of entries in the
      @io                                                     # central directory               8 bytes
      @io << [central_dir_size].pack(C_Qe)                    # size of the central directory   8 bytes
      @io                                                     # offset of start of central
      @io                                                     # directory with respect to
      @io << [start_of_central_directory].pack(C_Qe)          # the starting disk number        8 bytes
                                                              # zip64 extensible data sector    (variable size)

      # [zip64 end of central directory locator]
      @io << [0x07064b50].pack("V")                           # zip64 end of central dir locator
                                                              # signature                       4 bytes  (0x07064b50)
      @io << [0].pack(C_V)                                    # number of the disk with the
                                                              # start of the zip64 end of
                                                              # central directory               4 bytes
      @io << [zip64_eocdr_offset].pack(C_Qe)                  # relative offset of the zip64
                                                              # end of central directory record 8 bytes
      @io << [1].pack(C_V)                                    # total number of disks           4 bytes
    end

    # Then the end of central directory record:
    @io << [0x06054b50].pack(C_V)                           # end of central dir signature     4 bytes  (0x06054b50)
    @io << [0].pack(C_v)                                    # number of this disk              2 bytes
    @io << [0].pack(C_v)                                    # number of the disk with the
                                                            #   start of the central directory 2 bytes
    @io << [@files.length].pack(C_v)                        # total number of entries in the
                                                            # central directory on this disk   2 bytes
    @io << [@files.length].pack(C_v)                        # total number of entries in
                                                            # the central directory            2 bytes
    if zip64_required
      @io << [FOUR_BYTE_MAX_UINT].pack(C_V)                   # size of the central directory    4 bytes
      @io << [FOUR_BYTE_MAX_UINT].pack(C_V)                   # offset of start of central
                                                              # directory with respect to
                                                              # the starting disk number        4 bytes
    else
      @io << [central_dir_size].pack(C_V)                     # size of the central directory    4 bytes
      @io << [start_of_central_directory].pack(C_V)           # offset of start of central
                                                              # directory with respect to
                                                              # the starting disk number        4 bytes
    end
    @io << [0].pack(C_v)                                    # .ZIP file comment length        2 bytes
                                                            # .ZIP file comment       (variable size)
  end
  
  private_constant :FOUR_BYTE_MAX_UINT, :TWO_BYTE_MAX_UINT,
    :VERSION_MADE_BY, :VERSION_NEEDED_TO_EXTRACT, :VERSION_NEEDED_TO_EXTRACT_ZIP64, :Entry, :C_V, :C_v, :C_Qe
end
