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
  DEFAULT_EXTERNAL_ATTRS = begin
    # These need to be set so that the unarchived files do not become executable on UNIX, for
    # security purposes. Strictly speaking we would want to make this user-customizable,
    # but for now just putting in sane defaults will do. For example, Trac with zipinfo does this:
    # zipinfo.external_attr = 0644 << 16L # permissions -r-wr--r--.
    # We snatch the incantations from Rubyzip for this.
    unix_perms = 0644
    file_type_file = 010
    external_attrs = (file_type_file << 12 | (unix_perms & 07777)) << 16
  end
  MADE_BY_SIGNATURE = begin
    # A combination of the VERSION_MADE_BY low byte and the OS type high byte
    os_type = 3 # UNIX
    [VERSION_MADE_BY, os_type].pack('CC')
  end

  C_V = 'V'.freeze
  C_v = 'v'.freeze
  C_Qe = 'Q<'.freeze

  module Bytesize
    def bytesize_of
      ''.force_encoding(Encoding::BINARY).tap {|b| yield(b) }.bytesize
    end
  end
  include Bytesize
  
  class Entry < Struct.new(:filename, :crc32, :compressed_size, :uncompressed_size, :storage_mode, :mtime)
    include Bytesize
    def initialize(*)
      super
      @requires_zip64 = (compressed_size > FOUR_BYTE_MAX_UINT || uncompressed_size > FOUR_BYTE_MAX_UINT)
      if filename.bytesize > TWO_BYTE_MAX_UINT
        raise TooMuch, "The given filename is too long to fit (%d bytes)" % filename.bytesize
      end
    end

    def requires_zip64?
      @requires_zip64
    end
    
    # Set the general purpose flags for the entry. The only flag we care about is the EFS
    # bit (bit 11) which should be set if the filename is UTF8. If it is, we need to set the
    # bit so that the unarchiving application knows that the filename in the archive is UTF-8
    # encoded, and not some DOS default. For ASCII entries it does not matter.
    #
    # Now, strictly speaking, if a diacritic-containing character (such as å) does fit into the DOS-437
    # codepage, it should be encodable as such. This would, in theory, let older Windows tools
    # decode the filename correctly. However, this kills the filename decoding for the OSX builtin
    # archive utility (it assumes the filename to be UTF-8, regardless). So if we allow filenames
    # to be encoded in DOS-437, we _potentially_ have support in Windows but we upset everyone on Mac.
    # If we just use UTF-8 and set the right EFS bit in general purpose flags, we upset Windows users
    # because most of the Windows unarchive tools (at least the builtin ones) do not give a flying eff
    # about the EFS support bit being set.
    #
    # Additionally, if we use Unarchiver on OSX (which is our recommended unpacker for large files),
    # it will (very rightfully) ask us how we should decode each filename that does not have the EFS bit,
    # but does contain something non-ASCII-decodable. This is horrible UX for users.
    #
    # So, basically, we have 2 choices, for filenames containing diacritics (for bona-fide UTF-8 you do not
    # even get those choices, you _have_ to use UTF-8):
    #
    # * Make life easier for Windows users by setting stuff to DOS, not care about the standard _and_ make
    #   most of Mac users upset
    # * Make life easy for Mac users and conform to the standard, and tell Windows users to get a _decent_
    #   ZIP unarchiving tool.
    #
    # We are going with option 2, and this is well-thought-out. Trust me. If you want the crazytown
    # filename encoding scheme that is described here http://stackoverflow.com/questions/13261347
    # you can try this:
    #
    #  [Encoding::CP437, Encoding::ISO_8859_1, Encoding::UTF_8]
    #
    # We don't want no such thing, and sorry Windows users, you are going to need a decent unarchiver
    # that honors the standard. Alas, alas.
    def gp_flags_based_on_filename
      filename.encode(Encoding::ASCII)
      0b00000000000
    rescue EncodingError
      0b00000000000 | 0b100000000000
    end

    def write_local_file_header(io)
      # TBD: caveat. If this entry _does_ fit into a standard zip segment (both compressed and
      # uncompressed size at or below 0xFFFF etc), but it is _located_ at an offset that requires
      # Zip64 to be used (beyound 4GB), we are going to be omitting the Zip64 extras in the local
      # file header, but we will be enabling them when writing the central directory. Then the
      # CD record for the file _will_ have Zip64 extra, but the local file header won't. In theory,
      # this should not pose a problem, but then again... life in this world can be harsh.
      #
      # If it turns out that it _does_ pose a problem, we can always do:
      #
      #   @requires_zip64 = true if io.tell > FOUR_BYTE_MAX_UINT
      #
      # right here, and have the data written regardless even if the file fits.
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

      extra_size = 0
      if @requires_zip64
        extra_size += bytesize_of {|buf| write_zip_64_extra_for_local_file_header(buf) }
      end
      io << [extra_size].pack(C_v)                      # extra field length              2 bytes

      io << filename                                    # file name (variable size)

      # Interesting tidbit:
      # https://social.technet.microsoft.com/Forums/windows/en-US/6a60399f-2879-4859-b7ab-6ddd08a70948
      # TL;DR of it is: Windows 7 Explorer _will_ open Zip64 entries. However, it desires to have the
      # Zip64 extra field as _the first_ extra field. If we decide to add the Info-ZIP UTF-8 field...
      write_zip_64_extra_for_local_file_header(io) if @requires_zip64
    end

    def write_zip_64_extra_for_local_file_header(io)
      io << [0x0001].pack(C_v)                        # 2 bytes    Tag for this "extra" block type
      io << [16].pack(C_v)                            # 2 bytes    Size of this "extra" block. For us it will always be 16 (2x8)
      io << [uncompressed_size].pack(C_Qe)            # 8 bytes    Original uncompressed file size
      io << [compressed_size].pack(C_Qe)              # 8 bytes    Size of compressed data
    end

    def write_zip_64_extra_for_central_directory_file_header(io, local_file_header_location)
      io << [0x0001].pack(C_v)                        # 2 bytes    Tag for this "extra" block type
      io << [28].pack(C_v)                            # 2 bytes    Size of this "extra" block. For us it will always be 28
      io << [uncompressed_size].pack(C_Qe)            # 8 bytes    Original uncompressed file size
      io << [compressed_size].pack(C_Qe)              # 8 bytes    Size of compressed data
      io << [local_file_header_location].pack(C_Qe)   # 8 bytes    Offset of local header record
      io << [0].pack(C_V)                             # 4 bytes    Number of the disk on which this file starts
    end

    def write_central_directory_file_header(io, local_file_header_location)
      # At this point if the header begins somewhere beyound 0xFFFFFFFF we _have_ to record the offset
      # of the local file header as a zip64 extra field, so we give up, give in, you loose, love will always win...
      @requires_zip64 = true if local_file_header_location > FOUR_BYTE_MAX_UINT
      
      io << [0x02014b50].pack(C_V)                        # central file header signature   4 bytes  (0x02014b50)
      io << MADE_BY_SIGNATURE                             # version made by                 2 bytes
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

      extra_size = 0
      if @requires_zip64
        extra_size += bytesize_of {|buf|
          write_zip_64_extra_for_central_directory_file_header(buf, local_file_header_location)
        }
      end
      io << [extra_size].pack(C_v)                        # extra field length              2 bytes

      io << [0].pack(C_v)                                 # file comment length             2 bytes
      io << [0].pack(C_v)                                 # disk number start               2 bytes
      io << [0].pack(C_v)                                 # internal file attributes        2 bytes
      
      io << [DEFAULT_EXTERNAL_ATTRS].pack(C_V)           # external file attributes        4 bytes

      if @requires_zip64
        io << [FOUR_BYTE_MAX_UINT].pack(C_V)             # relative offset of local header 4 bytes
      else
        io << [local_file_header_location].pack(C_V)     # relative offset of local header 4 bytes
      end
      io << filename                                     # file name (variable size)

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
  def initialize
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
  def add_local_file_header(io:, filename:, crc32:, compressed_size:, uncompressed_size:, storage_mode:, mtime: Time.now.utc)
    if @files.any?{|e| e.filename == filename }
      raise DuplicateFilenames, "Filename #{filename.inspect} already used in the archive"
    end
    raise UnknownMode, "Unknown compression mode #{storage_mode}" unless [STORED, DEFLATED].include?(storage_mode)
    e = Entry.new(filename, crc32, compressed_size, uncompressed_size, storage_mode, mtime)
    @files << e
    @local_header_offsets << io.tell
    e.write_local_file_header(io)
  end

  # Writes the central directory (including the Zip6 salient bits if necessary)
  #
  # @return [void]
  def write_central_directory(io)
    start_of_central_directory = io.tell

    # Central directory file headers, per file in order
    @files.each_with_index do |file, i|
      local_file_header_offset_from_start_of_file = @local_header_offsets.fetch(i)
      file.write_central_directory_file_header(io, local_file_header_offset_from_start_of_file)
    end
    central_dir_size = io.tell - start_of_central_directory

    zip64_required = central_dir_size > FOUR_BYTE_MAX_UINT ||
      start_of_central_directory > FOUR_BYTE_MAX_UINT ||
      @files.length > TWO_BYTE_MAX_UINT ||
      @files.any?(&:requires_zip64?)

    # Then, if zip64 is used
    if zip64_required
      # [zip64 end of central directory record]
      zip64_eocdr_offset = io.tell
                                                # zip64 end of central dir
      io << [0x06064b50].pack(C_V)             # signature                       4 bytes  (0x06064b50)
      io << [44].pack(C_Qe)                    # size of zip64 end of central
                                                # directory record                8 bytes
                                                # (this is ex. the 12 bytes of the signature and the size value itself).
                                                # Without the extensible data sector it is always 44.
      io << MADE_BY_SIGNATURE                                # version made by                 2 bytes
      io << [VERSION_NEEDED_TO_EXTRACT_ZIP64].pack(C_v)      # version needed to extract       2 bytes
      io << [0].pack(C_V)                                    # number of this disk             4 bytes
      io << [0].pack(C_V)                                    # number of the disk with the
                                                             # start of the central directory  4 bytes
      io << [@files.length].pack(C_Qe)                       # total number of entries in the
                                                             # central directory on this disk  8 bytes
      io << [@files.length].pack(C_Qe)                       # total number of entries in the
                                                             # central directory               8 bytes
      io << [central_dir_size].pack(C_Qe)                    # size of the central directory   8 bytes
                                                             # offset of start of central
                                                             # directory with respect to
      io << [start_of_central_directory].pack(C_Qe)          # the starting disk number        8 bytes
                                                              # zip64 extensible data sector    (variable size)

      # [zip64 end of central directory locator]
      io << [0x07064b50].pack("V")                           # zip64 end of central dir locator
                                                             # signature                       4 bytes  (0x07064b50)
      io << [0].pack(C_V)                                    # number of the disk with the
                                                             # start of the zip64 end of
                                                             # central directory               4 bytes
      io << [zip64_eocdr_offset].pack(C_Qe)                  # relative offset of the zip64
                                                             # end of central directory record 8 bytes
                                                             # (note: "relative" is actually "from the start of the file")
      io << [1].pack(C_V)                                    # total number of disks           4 bytes
    end

    # Then the end of central directory record:
    io << [0x06054b50].pack(C_V)                            # end of central dir signature     4 bytes  (0x06054b50)
    io << [0].pack(C_v)                                     # number of this disk              2 bytes
    io << [0].pack(C_v)                                     # number of the disk with the
                                                            # start of the central directory 2 bytes
    
    if zip64_required # the number of entries will be read from the zip64 part of the central directory
      io << [TWO_BYTE_MAX_UINT].pack(C_v)                   # total number of entries in the
                                                            # central directory on this disk   2 bytes
      io << [TWO_BYTE_MAX_UINT].pack(C_v)                   # total number of entries in
                                                            # the central directory            2 bytes
    else
      io << [@files.length].pack(C_v)                       # total number of entries in the
                                                            # central directory on this disk   2 bytes
      io << [@files.length].pack(C_v)                       # total number of entries in
                                                            # the central directory            2 bytes
    end
    
    if zip64_required
      io << [FOUR_BYTE_MAX_UINT].pack(C_V)                  # size of the central directory    4 bytes
      io << [FOUR_BYTE_MAX_UINT].pack(C_V)                  # offset of start of central
                                                            # directory with respect to
                                                            # the starting disk number        4 bytes
    else
      io << [central_dir_size].pack(C_V)                    # size of the central directory    4 bytes
      io << [start_of_central_directory].pack(C_V)          # offset of start of central
                                                            # directory with respect to
                                                            # the starting disk number        4 bytes
    end
    io << [0].pack(C_v)                                     # .ZIP file comment length        2 bytes
                                                            # .ZIP file comment       (variable size)
  end
  
  private_constant :FOUR_BYTE_MAX_UINT, :TWO_BYTE_MAX_UINT,
    :VERSION_MADE_BY, :VERSION_NEEDED_TO_EXTRACT, :VERSION_NEEDED_TO_EXTRACT_ZIP64,
    :DEFAULT_EXTERNAL_ATTRS, :MADE_BY_SIGNATURE, 
    :Entry, :C_V, :C_v, :C_Qe
end
