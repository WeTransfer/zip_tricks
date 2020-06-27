# frozen_string_literal: true

# A low-level ZIP file data writer. You can use it to write out various headers and central directory elements
# separately. The class handles the actual encoding of the data according to the ZIP format APPNOTE document.
#
# The primary reason the writer is a separate object is because it is kept stateless. That is, all the data that
# is needed for writing a piece of the ZIP (say, the EOCD record, or a data descriptor) can be written
# without depending on data available elsewhere. This makes the writer very easy to test, since each of
# it's methods outputs something that only depends on the method's arguments. For example, we use this
# to test writing Zip64 files which, when tested in a streaming fashion, would need tricky IO stubs
# to wind IO objects back and forth by large offsets. Instead, we can just write out the EOCD record
# with given offsets as arguments.
#
# Since some methods need a lot of data about the entity being written, everything is passed via
# keyword arguments - this way it is much less likely that you can make a mistake writing something.
#
# Another reason for having a separate Writer is that most ZIP libraries attach the methods for
# writing out the file headers to some sort of Entry object, which represents a file within the ZIP.
# However, when you are diagnosing issues with the ZIP files you produce, you actually want to have
# absolute _most_ of the code responsible for writing the actual encoded bytes available to you on
# one screen. Altering or checking that code then becomes much, much easier. The methods doing the
# writing are also intentionally left very verbose - so that you can follow what is happening at
# all times.
#
# All methods of the writer accept anything that responds to `<<` as `io` argument - you can use
# that to output to String objects, or to output to Arrays that you can later join together.
class ZipTricks::ZipWriter
  FOUR_BYTE_MAX_UINT = 0xFFFFFFFF
  TWO_BYTE_MAX_UINT = 0xFFFF
  ZIP_TRICKS_COMMENT = 'Written using ZipTricks %<version>s' % {version: ZipTricks::VERSION}
  VERSION_MADE_BY                        = 52
  VERSION_NEEDED_TO_EXTRACT              = 20
  VERSION_NEEDED_TO_EXTRACT_ZIP64        = 45
  DEFAULT_EXTERNAL_ATTRS = begin
    # These need to be set so that the unarchived files do not become executable on UNIX, for
    # security purposes. Strictly speaking we would want to make this user-customizable,
    # but for now just putting in sane defaults will do. For example, Trac with zipinfo does this:
    # zipinfo.external_attr = 0644 << 16L # permissions -r-wr--r--.
    # We snatch the incantations from Rubyzip for this.
    unix_perms = 0o644
    file_type_file = 0o10
    (file_type_file << 12 | (unix_perms & 0o7777)) << 16
  end
  EMPTY_DIRECTORY_EXTERNAL_ATTRS = begin
    # Applies permissions to an empty directory.
    unix_perms = 0o755
    file_type_dir = 0o04
    (file_type_dir << 12 | (unix_perms & 0o7777)) << 16
  end
  MADE_BY_SIGNATURE = begin
    # A combination of the VERSION_MADE_BY low byte and the OS type high byte
    os_type = 3 # UNIX
    [VERSION_MADE_BY, os_type].pack('CC')
  end

  C_UINT4 = 'V'    # Encode a 4-byte unsigned little-endian uint
  C_UINT2 = 'v'    # Encode a 2-byte unsigned little-endian uint
  C_UINT8 = 'Q<'  # Encode an 8-byte unsigned little-endian uint
  C_CHAR = 'C' # For bit-encoded strings
  C_INT4 = 'l<' # Encode a 4-byte signed little-endian int

  private_constant :FOUR_BYTE_MAX_UINT,
                   :TWO_BYTE_MAX_UINT,
                   :VERSION_MADE_BY,
                   :VERSION_NEEDED_TO_EXTRACT,
                   :VERSION_NEEDED_TO_EXTRACT_ZIP64,
                   :DEFAULT_EXTERNAL_ATTRS,
                   :MADE_BY_SIGNATURE,
                   :C_UINT4,
                   :C_UINT2,
                   :C_UINT8,
                   :ZIP_TRICKS_COMMENT

  # Writes the local file header, that precedes the actual file _data_.
  #
  # @param io[#<<] the buffer to write the local file header to
  # @param filename[String]  the name of the file in the archive
  # @param compressed_size[Fixnum]    The size of the compressed (or stored) data - how much space it uses in the ZIP
  # @param uncompressed_size[Fixnum]  The size of the file once extracted
  # @param crc32[Fixnum] The CRC32 checksum of the file
  # @param mtime[Time]  the modification time to be recorded in the ZIP
  # @param gp_flags[Fixnum] bit-packed general purpose flags
  # @param storage_mode[Fixnum] 8 for deflated, 0 for stored...
  # @return [void]
  def write_local_file_header(io:, filename:, compressed_size:, uncompressed_size:, crc32:, gp_flags:, mtime:, storage_mode:)
    requires_zip64 = (compressed_size > FOUR_BYTE_MAX_UINT || uncompressed_size > FOUR_BYTE_MAX_UINT)

    io << [0x04034b50].pack(C_UINT4)                        # local file header signature     4 bytes  (0x04034b50)
    io << if requires_zip64                                 # version needed to extract       2 bytes
      [VERSION_NEEDED_TO_EXTRACT_ZIP64].pack(C_UINT2)
    else
      [VERSION_NEEDED_TO_EXTRACT].pack(C_UINT2)
    end

    io << [gp_flags].pack(C_UINT2)                          # general purpose bit flag        2 bytes
    io << [storage_mode].pack(C_UINT2)                      # compression method              2 bytes
    io << [to_binary_dos_time(mtime)].pack(C_UINT2)         # last mod file time              2 bytes
    io << [to_binary_dos_date(mtime)].pack(C_UINT2)         # last mod file date              2 bytes
    io << [crc32].pack(C_UINT4)                             # crc-32                          4 bytes

    if requires_zip64
      io << [FOUR_BYTE_MAX_UINT].pack(C_UINT4)              # compressed size              4 bytes
      io << [FOUR_BYTE_MAX_UINT].pack(C_UINT4)              # uncompressed size            4 bytes
    else
      io << [compressed_size].pack(C_UINT4)                 # compressed size              4 bytes
      io << [uncompressed_size].pack(C_UINT4)               # uncompressed size            4 bytes
    end

    # Filename should not be longer than 0xFFFF otherwise this wont fit here
    io << [filename.bytesize].pack(C_UINT2)                 # file name length             2 bytes

    extra_fields = StringIO.new

    # Interesting tidbit:
    # https://social.technet.microsoft.com/Forums/windows/en-US/6a60399f-2879-4859-b7ab-6ddd08a70948
    # TL;DR of it is: Windows 7 Explorer _will_ open Zip64 entries. However, it desires to have the
    # Zip64 extra field as _the first_ extra field.
    if requires_zip64
      extra_fields << zip_64_extra_for_local_file_header(compressed_size: compressed_size, uncompressed_size: uncompressed_size)
    end
    extra_fields << timestamp_extra_for_local_file_header(mtime)

    io << [extra_fields.size].pack(C_UINT2)                # extra field length              2 bytes

    io << filename                                     # file name (variable size)
    io << extra_fields.string
  end

  # Writes the file header for the central directory, for a particular file in the archive. When writing out this data,
  # ensure that the CRC32 and both sizes (compressed/uncompressed) are correct for the entry in question.
  #
  # @param io[#<<] the buffer to write the local file header to
  # @param filename[String]  the name of the file in the archive
  # @param compressed_size[Fixnum]    The size of the compressed (or stored) data - how much space it uses in the ZIP
  # @param uncompressed_size[Fixnum]  The size of the file once extracted
  # @param crc32[Fixnum] The CRC32 checksum of the file
  # @param mtime[Time]  the modification time to be recorded in the ZIP
  # @param gp_flags[Fixnum] bit-packed general purpose flags
  # @return [void]
  def write_central_directory_file_header(io:,
                                          local_file_header_location:,
                                          gp_flags:,
                                          storage_mode:,
                                          compressed_size:,
                                          uncompressed_size:,
                                          mtime:,
                                          crc32:,
                                          filename:)
    # At this point if the header begins somewhere beyound 0xFFFFFFFF we _have_ to record the offset
    # of the local file header as a zip64 extra field, so we give up, give in, you loose, love will always win...
    add_zip64 = (local_file_header_location > FOUR_BYTE_MAX_UINT) ||
                (compressed_size > FOUR_BYTE_MAX_UINT) || (uncompressed_size > FOUR_BYTE_MAX_UINT)

    io << [0x02014b50].pack(C_UINT4)                        # central file header signature   4 bytes  (0x02014b50)
    io << MADE_BY_SIGNATURE                             # version made by                 2 bytes
    io << if add_zip64
      [VERSION_NEEDED_TO_EXTRACT_ZIP64].pack(C_UINT2) # version needed to extract       2 bytes
    else
      [VERSION_NEEDED_TO_EXTRACT].pack(C_UINT2)       # version needed to extract       2 bytes
    end

    io << [gp_flags].pack(C_UINT2)                          # general purpose bit flag        2 bytes
    io << [storage_mode].pack(C_UINT2)                      # compression method              2 bytes
    io << [to_binary_dos_time(mtime)].pack(C_UINT2)         # last mod file time              2 bytes
    io << [to_binary_dos_date(mtime)].pack(C_UINT2)         # last mod file date              2 bytes
    io << [crc32].pack(C_UINT4)                             # crc-32                          4 bytes

    if add_zip64
      io << [FOUR_BYTE_MAX_UINT].pack(C_UINT4)              # compressed size              4 bytes
      io << [FOUR_BYTE_MAX_UINT].pack(C_UINT4)              # uncompressed size            4 bytes
    else
      io << [compressed_size].pack(C_UINT4)                 # compressed size              4 bytes
      io << [uncompressed_size].pack(C_UINT4)               # uncompressed size            4 bytes
    end

    # Filename should not be longer than 0xFFFF otherwise this wont fit here
    io << [filename.bytesize].pack(C_UINT2)                 # file name length                2 bytes

    extra_fields = StringIO.new
    if add_zip64
      extra_fields << zip_64_extra_for_central_directory_file_header(local_file_header_location: local_file_header_location,
                                                                     compressed_size: compressed_size,
                                                                     uncompressed_size: uncompressed_size)
    end
    extra_fields << timestamp_extra_for_central_directory_entry(mtime)

    io << [extra_fields.size].pack(C_UINT2)                 # extra field length              2 bytes

    io << [0].pack(C_UINT2)                                 # file comment length             2 bytes

    # For The Unarchiver < 3.11.1 this field has to be set to the overflow value if zip64 is used
    # because otherwise it does not properly advance the pointer when reading the Zip64 extra field
    # https://bitbucket.org/WAHa_06x36/theunarchiver/pull-requests/2/bug-fix-for-zip64-extra-field-parser/diff
    io << if add_zip64                                        # disk number start               2 bytes
      [TWO_BYTE_MAX_UINT].pack(C_UINT2)
    else
      [0].pack(C_UINT2)
    end
    io << [0].pack(C_UINT2)                                # internal file attributes        2 bytes

    # Because the add_empty_directory method will create a directory with a trailing "/",
    # this check can be used to assign proper permissions to the created directory.
    io << if filename.end_with?('/')
      [EMPTY_DIRECTORY_EXTERNAL_ATTRS].pack(C_UINT4)
    else
      [DEFAULT_EXTERNAL_ATTRS].pack(C_UINT4)           # external file attributes        4 bytes
    end

    io << if add_zip64                                 # relative offset of local header 4 bytes
      [FOUR_BYTE_MAX_UINT].pack(C_UINT4)
    else
      [local_file_header_location].pack(C_UINT4)
    end

    io << filename                                     # file name (variable size)
    io << extra_fields.string                          # extra field (variable size)
    # (empty)                                          # file comment (variable size)
  end

  # Writes the data descriptor following the file data for a file whose local file header
  # was written with general-purpose flag bit 3 set. If the one of the sizes exceeds the Zip64 threshold,
  # the data descriptor will have the sizes written out as 8-byte values instead of 4-byte values.
  #
  # @param io[#<<] the buffer to write the local file header to
  # @param crc32[Fixnum]    The CRC32 checksum of the file
  # @param compressed_size[Fixnum]    The size of the compressed (or stored) data - how much space it uses in the ZIP
  # @param uncompressed_size[Fixnum]  The size of the file once extracted
  # @return [void]
  def write_data_descriptor(io:, compressed_size:, uncompressed_size:, crc32:)
    io << [0x08074b50].pack(C_UINT4)  # Although not originally assigned a signature, the value
    # 0x08074b50 has commonly been adopted as a signature value
    # for the data descriptor record.
    io << [crc32].pack(C_UINT4)                             # crc-32                          4 bytes

    # If one of the sizes is above 0xFFFFFFF use ZIP64 lengths (8 bytes) instead. A good unarchiver
    # will decide to unpack it as such if it finds the Zip64 extra for the file in the central directory.
    # So also use the opportune moment to switch the entry to Zip64 if needed
    requires_zip64 = (compressed_size > FOUR_BYTE_MAX_UINT || uncompressed_size > FOUR_BYTE_MAX_UINT)
    pack_spec = requires_zip64 ? C_UINT8 : C_UINT4

    io << [compressed_size].pack(pack_spec)       # compressed size                 4 bytes, or 8 bytes for ZIP64
    io << [uncompressed_size].pack(pack_spec)     # uncompressed size               4 bytes, or 8 bytes for ZIP64
  end

  # Writes the "end of central directory record" (including the Zip6 salient bits if necessary)
  #
  # @param io[#<<] the buffer to write the central directory to.
  # @param start_of_central_directory_location[Fixnum] byte offset of the start of central directory form the beginning of ZIP file
  # @param central_directory_size[Fixnum] the size of the central directory (only file headers) in bytes
  # @param num_files_in_archive[Fixnum] How many files the archive contains
  # @param comment[String] the comment for the archive (defaults to ZIP_TRICKS_COMMENT)
  # @return [void]
  def write_end_of_central_directory(io:, start_of_central_directory_location:, central_directory_size:, num_files_in_archive:, comment: ZIP_TRICKS_COMMENT)
    zip64_eocdr_offset = start_of_central_directory_location + central_directory_size

    zip64_required = central_directory_size > FOUR_BYTE_MAX_UINT ||
                     start_of_central_directory_location > FOUR_BYTE_MAX_UINT ||
                     zip64_eocdr_offset > FOUR_BYTE_MAX_UINT ||
                     num_files_in_archive > TWO_BYTE_MAX_UINT

    # Then, if zip64 is used
    if zip64_required
      # [zip64 end of central directory record]
      # zip64 end of central dir
      io << [0x06064b50].pack(C_UINT4)                           # signature                       4 bytes  (0x06064b50)
      io << [44].pack(C_UINT8)                                  # size of zip64 end of central
      # directory record                8 bytes
      # (this is ex. the 12 bytes of the signature and the size value itself).
      # Without the extensible data sector (which we are not using)
      # it is always 44 bytes.
      io << MADE_BY_SIGNATURE                                # version made by                 2 bytes
      io << [VERSION_NEEDED_TO_EXTRACT_ZIP64].pack(C_UINT2)      # version needed to extract       2 bytes
      io << [0].pack(C_UINT4)                                    # number of this disk             4 bytes
      io << [0].pack(C_UINT4)                                    # number of the disk with the
      # start of the central directory  4 bytes
      io << [num_files_in_archive].pack(C_UINT8)                # total number of entries in the
      # central directory on this disk  8 bytes
      io << [num_files_in_archive].pack(C_UINT8)                # total number of entries in the
      # central directory               8 bytes
      io << [central_directory_size].pack(C_UINT8)              # size of the central directory   8 bytes
      # offset of start of central
      # directory with respect to
      io << [start_of_central_directory_location].pack(C_UINT8) # the starting disk number        8 bytes
      # zip64 extensible data sector    (variable size), blank for us

      # [zip64 end of central directory locator]
      io << [0x07064b50].pack(C_UINT4)                           # zip64 end of central dir locator
      # signature                       4 bytes  (0x07064b50)
      io << [0].pack(C_UINT4)                                    # number of the disk with the
      # start of the zip64 end of
      # central directory               4 bytes
      io << [zip64_eocdr_offset].pack(C_UINT8)                  # relative offset of the zip64
      # end of central directory record 8 bytes
      # (note: "relative" is actually "from the start of the file")
      io << [1].pack(C_UINT4)                                    # total number of disks           4 bytes
    end

    # Then the end of central directory record:
    io << [0x06054b50].pack(C_UINT4)                            # end of central dir signature     4 bytes  (0x06054b50)
    io << [0].pack(C_UINT2)                                     # number of this disk              2 bytes
    io << [0].pack(C_UINT2)                                     # number of the disk with the
    # start of the central directory 2 bytes

    if zip64_required # the number of entries will be read from the zip64 part of the central directory
      io << [TWO_BYTE_MAX_UINT].pack(C_UINT2)                   # total number of entries in the
      # central directory on this disk   2 bytes
      io << [TWO_BYTE_MAX_UINT].pack(C_UINT2)                   # total number of entries in
    # the central directory            2 bytes
    else
      io << [num_files_in_archive].pack(C_UINT2)                # total number of entries in the
      # central directory on this disk   2 bytes
      io << [num_files_in_archive].pack(C_UINT2)                # total number of entries in
      # the central directory            2 bytes
    end

    if zip64_required
      io << [FOUR_BYTE_MAX_UINT].pack(C_UINT4)                  # size of the central directory    4 bytes
      io << [FOUR_BYTE_MAX_UINT].pack(C_UINT4)                  # offset of start of central
    # directory with respect to
    # the starting disk number        4 bytes
    else
      io << [central_directory_size].pack(C_UINT4)              # size of the central directory    4 bytes
      io << [start_of_central_directory_location].pack(C_UINT4) # offset of start of central
      # directory with respect to
      # the starting disk number        4 bytes
    end
    io << [comment.bytesize].pack(C_UINT2)                      # .ZIP file comment length        2 bytes
    io << comment                                           # .ZIP file comment       (variable size)
  end

  private

  # Writes the Zip64 extra field for the local file header. Will be used by `write_local_file_header` when any sizes given to it warrant that.
  #
  # @param compressed_size[Fixnum]    The size of the compressed (or stored) data - how much space it uses in the ZIP
  # @param uncompressed_size[Fixnum]  The size of the file once extracted
  # @return [String]
  def zip_64_extra_for_local_file_header(compressed_size:, uncompressed_size:)
    data_and_packspecs = [
      0x0001, C_UINT2,                       # 2 bytes    Tag for this "extra" block type
      16, C_UINT2,                           # 2 bytes    Size of this "extra" block. For us it will always be 16 (2x8)
      uncompressed_size, C_UINT8,           # 8 bytes    Original uncompressed file size
      compressed_size, C_UINT8,             # 8 bytes    Size of compressed data
    ]
    pack_array(data_and_packspecs)
  end

  # Writes the extended timestamp information field for local headers.
  #
  # The spec defines 2
  # different formats - the one for the local file header can also accomodate the
  # atime and ctime, whereas the one for the central directory can only take
  # the mtime - and refers the reader to the local header extra to obtain the
  # remaining times
  def timestamp_extra_for_local_file_header(mtime)
    #         Local-header version:
    #
    #         Value         Size        Description
    #         -----         ----        -----------
    # (time)  0x5455        Short       tag for this extra block type ("UT")
    #         TSize         Short       total data size for this block
    #         Flags         Byte        info bits
    #         (ModTime)     Long        time of last modification (UTC/GMT)
    #         (AcTime)      Long        time of last access (UTC/GMT)
    #         (CrTime)      Long        time of original creation (UTC/GMT)
    #
    #         Central-header version:
    #
    #         Value         Size        Description
    #         -----         ----        -----------
    # (time)  0x5455        Short       tag for this extra block type ("UT")
    #         TSize         Short       total data size for this block
    #         Flags         Byte        info bits (refers to local header!)
    #         (ModTime)     Long        time of last modification (UTC/GMT)
    #
    # The lower three bits of Flags in both headers indicate which time-
    #       stamps are present in the LOCAL extra field:
    #
    #       bit 0           if set, modification time is present
    #       bit 1           if set, access time is present
    #       bit 2           if set, creation time is present
    #       bits 3-7        reserved for additional timestamps; not set
    flags = 0b00000001 # Set the lowest bit only, to indicate that only mtime is present
    data_and_packspecs = [
      0x5455, C_UINT2,  # tag for this extra block type ("UT")
      (1 + 4), C_UINT2, # the size of this block (1 byte used for the Flag + 3 longs used for the timestamp)
      flags, C_CHAR,   # encode a single byte
      mtime.utc.to_i, C_INT4, # Use a signed int, not the unsigned one used by the rest of the ZIP spec.
    ]
    # The atime and ctime can be omitted if not present
    pack_array(data_and_packspecs)
  end

  # Since we do not supply atime or ctime, the contents of the two extra fields (central dir and local header)
  # is exactly the same, so we can use a method alias.
  alias_method :timestamp_extra_for_central_directory_entry, :timestamp_extra_for_local_file_header

  # Writes the Zip64 extra field for the central directory header.It differs from the extra used in the local file header because it
  # also contains the location of the local file header in the ZIP as an 8-byte int.
  #
  # @param compressed_size[Fixnum]    The size of the compressed (or stored) data - how much space it uses in the ZIP
  # @param uncompressed_size[Fixnum]  The size of the file once extracted
  # @param local_file_header_location[Fixnum] Byte offset of the start of the local file header from the beginning of the ZIP archive
  # @return [String]
  def zip_64_extra_for_central_directory_file_header(compressed_size:, uncompressed_size:, local_file_header_location:)
    data_and_packspecs = [
      0x0001, C_UINT2,                        # 2 bytes    Tag for this "extra" block type
      28,     C_UINT2,                        # 2 bytes    Size of this "extra" block. For us it will always be 28
      uncompressed_size, C_UINT8,            # 8 bytes    Original uncompressed file size
      compressed_size,   C_UINT8,            # 8 bytes    Size of compressed data
      local_file_header_location, C_UINT8,   # 8 bytes    Offset of local header record
      0, C_UINT4,                             # 4 bytes    Number of the disk on which this file starts
    ]
    pack_array(data_and_packspecs)
  end

  def to_binary_dos_time(t)
    (t.sec / 2) + (t.min << 5) + (t.hour << 11)
  end

  def to_binary_dos_date(t)
    t.day + (t.month << 5) + ((t.year - 1980) << 9)
  end

  # Unzips a given array of tuples of "numeric value, pack specifier" and then packs all the odd
  # values using specifiers from all the even values. It is harder to explain than to show:
  #
  #   pack_array([1, 'V', 2, 'v', 148, 'v]) #=> "\x01\x00\x00\x00\x02\x00\x94\x00"
  #
  # will do the following two transforms:
  #
  #  [1, 'V', 2, 'v', 148, 'v] -> [1,2,148], ['V','v','v'] -> [1,2,148].pack('Vvv') -> "\x01\x00\x00\x00\x02\x00\x94\x00"
  def pack_array(values_to_packspecs)
    values, packspecs = values_to_packspecs.partition.each_with_index { |_, i| i.even? }
    values.pack(packspecs.join)
  end
end
