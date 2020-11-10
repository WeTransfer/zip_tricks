# frozen_string_literal: true

require 'stringio'

# A very barebones ZIP file reader. Is made for maximum interoperability, but at the same
# time we attempt to keep it somewhat concise.
#
# ## REALLY CRAZY IMPORTANT STUFF: SECURITY IMPLICATIONS
#
# Please **BEWARE** - using this is a security risk if you are reading files that have been
# supplied by users. This implementation has _not_ been formally verified for correctness. As
# ZIP files contain relative offsets in lots of places it might be possible for a maliciously
# crafted ZIP file to put the decode procedure in an endless loop, make it attempt huge reads
# from the input file and so on. Additionally, the reader module for deflated data has
# no support for ZIP bomb protection. So either limit the `FileReader` usage to the files you
# trust, or triple-check all the inputs upfront. Patches to make this reader more secure
# are welcome of course.
#
# ## Usage
#
#     File.open('zipfile.zip', 'rb') do |f|
#       entries = ZipTricks::FileReader.read_zip_structure(io: f)
#       entries.each do |e|
#         File.open(e.filename, 'wb') do |extracted_file|
#           ex = e.extractor_from(f)
#           extracted_file << ex.extract(1024 * 1024) until ex.eof?
#         end
#       end
#     end
#
# ## Supported features
#
# * Deflate and stored storage modes
# * Zip64 (extra fields and offsets)
# * Data descriptors
#
# ## Unsupported features
#
# * Archives split over multiple disks/files
# * Any ZIP encryption
# * EFS language flag and InfoZIP filename extra field
# * CRC32 checksums are _not_ verified
#
# ## Mode of operation
#
# By default, `FileReader` _ignores_ the data in local file headers (as it is
# often unreliable). It reads the ZIP file "from the tail", finds the
# end-of-central-directory signatures, then reads the central directory entries,
# reconstitutes the entries with their filenames, attributes and so on, and
# sets these entries up with the absolute _offsets_ into the source file/IO object.
# These offsets can then be used to extract the actual compressed data of
# the files and to expand it.
#
# ## Recovering damaged or incomplete ZIP files
#
# If the ZIP file you are trying to read does not contain the central directory
# records `read_zip_structure` will not work, since it starts the read process
# from the EOCD marker at the end of the central directory and then crawls
# "back" in the IO to figure out the rest. You can explicitly apply a fallback
# for reading the archive "straight ahead" instead using `read_zip_straight_ahead`
# - the method will instead scan your IO from the very start, skipping over
# the actual entry data. This is less efficient than central directory parsing since
# it involves a much larger number of reads (1 read from the IO per entry in the ZIP).

class ZipTricks::FileReader
  require_relative 'file_reader/stored_reader'
  require_relative 'file_reader/inflating_reader'

  ReadError = Class.new(StandardError)
  UnsupportedFeature = Class.new(StandardError)
  InvalidStructure = Class.new(ReadError)
  LocalHeaderPending = Class.new(StandardError) do
    def message
      'The compressed data offset is not available (local header has not been read)'
    end
  end
  MissingEOCD = Class.new(StandardError) do
    def message
      'Could not find the EOCD signature in the buffer - maybe a malformed ZIP file'
    end
  end

  private_constant :StoredReader, :InflatingReader

  # Represents a file within the ZIP archive being read. This is different from
  # the Entry object used in Streamer for ZIP writing, since during writing more
  # data can be kept in memory for immediate use.
  class ZipEntry
    # @return [Fixnum] bit-packed version signature of the program that made the archive
    attr_accessor :made_by

    # @return [Fixnum] ZIP version support needed to extract this file
    attr_accessor :version_needed_to_extract

    # @return [Fixnum] bit-packed general purpose flags
    attr_accessor :gp_flags

    # @return [Fixnum] Storage mode (0 for stored, 8 for deflate)
    attr_accessor :storage_mode

    # @return [Fixnum] the bit-packed DOS time
    attr_accessor :dos_time

    # @return [Fixnum] the bit-packed DOS date
    attr_accessor :dos_date

    # @return [Fixnum] the CRC32 checksum of this file
    attr_accessor :crc32

    # @return [Fixnum] size of compressed file data in the ZIP
    attr_accessor :compressed_size

    # @return [Fixnum] size of the file once uncompressed
    attr_accessor :uncompressed_size

    # @return [String] the filename
    attr_accessor :filename

    # @return [Fixnum] disk number where this file starts
    attr_accessor :disk_number_start

    # @return [Fixnum] internal attributes of the file
    attr_accessor :internal_attrs

    # @return [Fixnum] external attributes of the file
    attr_accessor :external_attrs

    # @return [Fixnum] at what offset the local file header starts
    #        in your original IO object
    attr_accessor :local_file_header_offset

    # @return [String] the file comment
    attr_accessor :comment

    # Returns a reader for the actual compressed data of the entry.
    #
    #   reader = entry.extractor_from(source_file)
    #   outfile << reader.extract(512 * 1024) until reader.eof?
    #
    # @return [#extract(n_bytes), #eof?] the reader for the data
    def extractor_from(from_io)
      from_io.seek(compressed_data_offset, IO::SEEK_SET)
      case storage_mode
      when 8
        InflatingReader.new(from_io, compressed_size)
      when 0
        StoredReader.new(from_io, compressed_size)
      else
        raise UnsupportedFeature, 'Unsupported storage mode for reading - %<storage_mode>d' %
                                  {storage_mode: storage_mode}
      end
    end

    # @return [Fixnum] at what offset you should start reading
    #       for the compressed data in your original IO object
    def compressed_data_offset
      @compressed_data_offset || raise(LocalHeaderPending)
    end

    # Tells whether the compressed data offset is already known for this entry
    # @return [Boolean]
    def known_offset?
      !@compressed_data_offset.nil?
    end

    # Tells whether the entry uses a data descriptor (this is defined
    # by bit 3 in the GP flags).
    def uses_data_descriptor?
      (gp_flags & 0x0008) == 0x0008
    end

    # Sets the offset at which the compressed data for this file starts in the ZIP.
    # By default, the value will be set by the Reader for you. If you use delayed
    # reading, you need to set it by using the `get_compressed_data_offset` on the Reader:
    #
    #     entry.compressed_data_offset = reader.get_compressed_data_offset(io: file,
    #            local_file_header_offset: entry.local_header_offset)
    def compressed_data_offset=(offset)
      @compressed_data_offset = offset.to_i
    end
  end

  # Parse an IO handle to a ZIP archive into an array of Entry objects.
  #
  # @param io[#tell, #seek, #read, #size] an IO-ish object
  # @param read_local_headers[Boolean] whether the local headers must be read upfront. When reading
  #   a locally available ZIP file this option will not have much use since the small reads from
  #   the file handle are not going to be that important. However, if you are using remote reads
  #   to decipher a ZIP file located on an HTTP server, the operation _must_ perform an HTTP
  #   request for _each entry in the ZIP file_ to determine where the actual file data starts.
  #   This, for a ZIP archive of 1000 files, will incur 1000 extra HTTP requests - which you might
  #   not want to perform upfront, or - at least - not want to perform _at once_. When the option is
  #   set to `false`, you will be getting instances of `LazyEntry` instead of `Entry`. Those objects
  #   will raise an exception when you attempt to access their compressed data offset in the ZIP
  #   (since the reads have not been performed yet). As a rule, this option can be left in it's
  #   default setting (`true`) unless you want to _only_ read the central directory, or you need
  #   to limit the number of HTTP requests.
  # @return [Array<ZipEntry>] an array of entries within the ZIP being parsed
  def read_zip_structure(io:, read_local_headers: true)
    zip_file_size = io.size
    eocd_offset = get_eocd_offset(io, zip_file_size)

    zip64_end_of_cdir_location = get_zip64_eocd_location(io, eocd_offset)
    num_files, cdir_location, _cdir_size =
      if zip64_end_of_cdir_location
        num_files_and_central_directory_offset_zip64(io, zip64_end_of_cdir_location)
      else
        num_files_and_central_directory_offset(io, eocd_offset)
      end

    log do
      'Located the central directory start at %<location>d' %
        {location: cdir_location}
    end
    seek(io, cdir_location)

    # Read the entire central directory AND anything behind it, in one fell swoop.
    # Strictly speaking, we should be able to read `cdir_size` bytes and not a byte more.
    # However, we know for a fact that in some of our files the central directory size
    # is in fact misreported. `zipinfo` then says:
    #
    #    warning [ktsglobal-2b03bc.zip]:  1 extra byte at beginning or within zipfile
    #      (attempting to process anyway)
    #    error [ktsglobal-2b03bc.zip]:  reported length of central directory is
    #      -1 bytes too long (Atari STZip zipfile?  J.H.Holm ZIPSPLIT 1.1
    #      zipfile?).  Compensating...
    #
    # Since the EOCD is not that big anyway, we just read the entire "tail" of the ZIP ignoring
    # the central directory size alltogether.
    central_directory_str = io.read # and not read_n(io, cdir_size), see above
    central_directory_io = StringIO.new(central_directory_str)
    log do
      'Read %<byte_size>d bytes with central directory + EOCD record and locator' %
        {byte_size: central_directory_str.bytesize}
    end

    entries = (0...num_files).map do |entry_n|
      offset_location = cdir_location + central_directory_io.tell
      log do
        'Reading the central directory entry %<entry_n>d starting at offset %<offset>d' %
          {entry_n: entry_n, offset: offset_location}
      end
      read_cdir_entry(central_directory_io)
    end

    read_local_headers(entries, io) if read_local_headers

    entries
  end

  # Sometimes you might encounter truncated ZIP files, which do not contain
  # any central directory whatsoever - or where the central directory is
  # truncated. In that case, employing the technique of reading the ZIP
  # "from the end" is impossible, and the only recourse is reading each
  # local file header in sucession. If the entries in such a ZIP use data
  # descriptors, you would need to scan after the entry until you encounter
  # the data descriptor signature - and that might be unreliable at best.
  # Therefore, this reading technique does not support data descriptors.
  # It can however recover the entries you still can read if these entries
  # contain all the necessary information about the contained file.
  #
  # @param io[#tell, #read, #seek] the IO-ish object to read the local file
  # headers from @return [Array<ZipEntry>] an array of entries that could be
  # recovered before hitting EOF
  def read_zip_straight_ahead(io:)
    entries = []
    loop do
      cur_offset = io.tell
      entry = read_local_file_header(io: io)
      if entry.uses_data_descriptor?
        raise UnsupportedFeature, "The local file header at #{cur_offset} uses \
                                  a data descriptor and the start of next entry \
                                  cannot be found"
      end
      entries << entry
      next_local_header_offset = entry.compressed_data_offset + entry.compressed_size
      log do
        'Recovered a local file file header at offset %<cur_offset>d, seeking to the next at %<header_offset>d' %
          {cur_offset: cur_offset, header_offset: next_local_header_offset}
      end
      seek(io, next_local_header_offset) # Seek to the next entry, and raise if seek is impossible
    end
    entries
  rescue ReadError, RangeError # RangeError is raised if offset exceeds int32/int64 range
    log do
      'Got a read/seek error after reaching %<cur_offset>d, no more entries can be recovered' %
        {cur_offset: cur_offset}
    end
    entries
  end

  # Parse the local header entry and get the offset in the IO at which the
  # actual compressed data of the file starts within the ZIP.
  # The method will eager-read the entire local header for the file
  # (the maximum size the local header may use), starting at the given offset,
  # and will then compute its size. That size plus the local header offset
  # given will be the compressed data offset of the entry (read starting at
  # this offset to get the data).
  #
  # @param io[#read] an IO-ish object the ZIP file can be read from
  # @return [Array<ZipEntry, Fixnum>] the parsed local header entry and
  # the compressed data offset
  def read_local_file_header(io:)
    local_file_header_offset = io.tell

    # Reading in bulk is cheaper - grab the maximum length of the local header,
    # including any headroom for extra fields etc.
    local_file_header_str_plus_headroom = io.read(MAX_LOCAL_HEADER_SIZE)
    raise ReadError if local_file_header_str_plus_headroom.nil? # reached EOF

    io_starting_at_local_header = StringIO.new(local_file_header_str_plus_headroom)

    assert_signature(io_starting_at_local_header, 0x04034b50)
    e = ZipEntry.new
    e.version_needed_to_extract = read_2b(io_starting_at_local_header) # Version needed to extract
    e.gp_flags = read_2b(io_starting_at_local_header) # gp flags
    e.storage_mode = read_2b(io_starting_at_local_header) # storage mode
    e.dos_time = read_2b(io_starting_at_local_header) # dos time
    e.dos_date = read_2b(io_starting_at_local_header) # dos date
    e.crc32 = read_4b(io_starting_at_local_header) # CRC32
    e.compressed_size = read_4b(io_starting_at_local_header) # Comp size
    e.uncompressed_size = read_4b(io_starting_at_local_header) # Uncomp size

    filename_size = read_2b(io_starting_at_local_header)
    extra_size = read_2b(io_starting_at_local_header)
    e.filename = read_n(io_starting_at_local_header, filename_size)
    extra_fields_str = read_n(io_starting_at_local_header, extra_size)

    # Parse out the extra fields
    extra_table = parse_out_extra_fields(extra_fields_str)

    # ...of which we really only need the Zip64 extra
    if zip64_extra_contents = extra_table[1]
      # If the Zip64 extra is present, we let it override all
      # the values fetched from the conventional header
      zip64_extra = StringIO.new(zip64_extra_contents)
      log do
        'Will read Zip64 extra data from local header field for %<filename>s, %<size>d bytes' %
          {filename: e.filename, size: zip64_extra.size}
      end
      # Now here be dragons. The APPNOTE specifies that
      #
      # > The order of the fields in the ZIP64 extended
      # > information record is fixed, but the fields will
      # > only appear if the corresponding Local or Central
      # > directory record field is set to 0xFFFF or 0xFFFFFFFF.
      #
      # It means that before we read this stuff we need to check if the previously-read
      # values are at overflow, and only _then_ proceed to read them. Bah.
      e.uncompressed_size = read_8b(zip64_extra) if e.uncompressed_size == 0xFFFFFFFF
      e.compressed_size = read_8b(zip64_extra) if e.compressed_size == 0xFFFFFFFF
    end

    offset = local_file_header_offset + io_starting_at_local_header.tell
    e.compressed_data_offset = offset

    e
  end

  # Get the offset in the IO at which the actual compressed data of the file
  # starts within the ZIP. The method will eager-read the entire local header
  # for the file (the maximum size the local header may use), starting at the
  # given offset, and will then compute its size. That size plus the local
  # header offset given will be the compressed data offset of the entry
  # (read starting at this offset to get the data).
  #
  # @param io[#seek, #read] an IO-ish object the ZIP file can be read from
  # @param local_file_header_offset[Fixnum] absolute offset (0-based) where the
  # local file header is supposed to begin @return [Fixnum] absolute offset
  # (0-based) of where the compressed data begins for this file within the ZIP
  def get_compressed_data_offset(io:, local_file_header_offset:)
    seek(io, local_file_header_offset)
    entry_recovered_from_local_file_header = read_local_file_header(io: io)
    entry_recovered_from_local_file_header.compressed_data_offset
  end

  # Parse an IO handle to a ZIP archive into an array of Entry objects, reading from the end
  # of the IO object.
  #
  # @see #read_zip_structure
  # @param options[Hash] any options the instance method of the same name accepts
  # @return [Array<ZipEntry>] an array of entries within the ZIP being parsed
  def self.read_zip_structure(**options)
    new.read_zip_structure(**options)
  end

  # Parse an IO handle to a ZIP archive into an array of Entry objects, reading from the start of
  # the file and parsing local file headers one-by-one
  #
  # @see #read_zip_straight_ahead
  # @param options[Hash] any options the instance method of the same name accepts
  # @return [Array<ZipEntry>] an array of entries within the ZIP being parsed
  def self.read_zip_straight_ahead(**options)
    new.read_zip_straight_ahead(**options)
  end

  private

  def read_local_headers(entries, io)
    entries.each_with_index do |entry, i|
      log do
        'Reading the local header for entry %<index>d at offset %<offset>d' %
          {index: i, offset: entry.local_file_header_offset}
      end
      off = get_compressed_data_offset(io: io,
                                       local_file_header_offset: entry.local_file_header_offset)
      entry.compressed_data_offset = off
    end
  end

  def skip_ahead_2(io)
    skip_ahead_n(io, 2)
  end

  def skip_ahead_4(io)
    skip_ahead_n(io, 4)
  end

  def skip_ahead_8(io)
    skip_ahead_n(io, 8)
  end

  def seek(io, absolute_pos)
    io.seek(absolute_pos, IO::SEEK_SET)
    unless absolute_pos == io.tell
      raise ReadError,
            "Expected to seek to #{absolute_pos} but only \
             got to #{io.tell}"
    end
    nil
  end

  def assert_signature(io, signature_magic_number)
    readback = read_4b(io)
    if readback != signature_magic_number
      expected = '0x0' + signature_magic_number.to_s(16)
      actual = '0x0' + readback.to_s(16)
      raise InvalidStructure, "Expected signature #{expected}, but read #{actual}"
    end
  end

  def skip_ahead_n(io, n)
    pos_before = io.tell
    io.seek(io.tell + n, IO::SEEK_SET)
    pos_after = io.tell
    delta = pos_after - pos_before
    unless delta == n
      raise ReadError, "Expected to seek #{n} bytes ahead, but could \
                        only seek #{delta} bytes ahead"
    end
    nil
  end

  def read_n(io, n_bytes)
    io.read(n_bytes).tap do |d|
      raise ReadError, "Expected to read #{n_bytes} bytes, but the IO was at the end" if d.nil?
      unless d.bytesize == n_bytes
        raise ReadError, "Expected to read #{n_bytes} bytes, \
                          read #{d.bytesize}"
      end
    end
  end

  def read_2b(io)
    read_n(io, 2).unpack(C_UINT2).shift
  end

  def read_4b(io)
    read_n(io, 4).unpack(C_UINT4).shift
  end

  def read_8b(io)
    read_n(io, 8).unpack(C_UINT8).shift
  end

  def read_cdir_entry(io)
    # read_cdir_entry is too high. [45.66/15]
    assert_signature(io, 0x02014b50)
    ZipEntry.new.tap do |e|
      e.made_by = read_2b(io)
      e.version_needed_to_extract = read_2b(io)
      e.gp_flags = read_2b(io)
      e.storage_mode = read_2b(io)
      e.dos_time = read_2b(io)
      e.dos_date = read_2b(io)
      e.crc32 = read_4b(io)
      e.compressed_size = read_4b(io)
      e.uncompressed_size = read_4b(io)
      filename_size = read_2b(io)
      extra_size = read_2b(io)
      comment_len = read_2b(io)
      e.disk_number_start = read_2b(io)
      e.internal_attrs = read_2b(io)
      e.external_attrs = read_4b(io)
      e.local_file_header_offset = read_4b(io)
      e.filename = read_n(io, filename_size)

      # Extra fields
      extras = read_n(io, extra_size)
      # Comment
      e.comment = read_n(io, comment_len)

      # Parse out the extra fields
      extra_table = parse_out_extra_fields(extras)

      # ...of which we really only need the Zip64 extra
      if zip64_extra_contents ||= extra_table[1]
        # If the Zip64 extra is present, we let it override all
        # the values fetched from the conventional header
        zip64_extra = StringIO.new(zip64_extra_contents)
        log do
          'Will read Zip64 extra data for %<filename>s, %<size>d bytes' %
            {filename: e.filename, size: zip64_extra.size}
        end
        # Now here be dragons. The APPNOTE specifies that
        #
        # > The order of the fields in the ZIP64 extended
        # > information record is fixed, but the fields will
        # > only appear if the corresponding Local or Central
        # > directory record field is set to 0xFFFF or 0xFFFFFFFF.
        #
        # It means that before we read this stuff we need to check if the previously-read
        # values are at overflow, and only _then_ proceed to read them. Bah.
        e.uncompressed_size = read_8b(zip64_extra) if e.uncompressed_size == 0xFFFFFFFF
        e.compressed_size = read_8b(zip64_extra) if e.compressed_size == 0xFFFFFFFF
        e.local_file_header_offset = read_8b(zip64_extra) if e.local_file_header_offset == 0xFFFFFFFF
        # Disk number comes last and we can skip it anyway, since we do
        # not support multi-disk archives
      end
    end
  end

  def get_eocd_offset(file_io, zip_file_size)
    # Start reading from the _comment_ of the zip file (from the very end).
    # The maximum size of the comment is 0xFFFF (what fits in 2 bytes)
    implied_position_of_eocd_record = zip_file_size - MAX_END_OF_CENTRAL_DIRECTORY_RECORD_SIZE
    implied_position_of_eocd_record = 0 if implied_position_of_eocd_record < 0

    # Use a soft seek (we might not be able to get as far behind in the IO as we want)
    # and a soft read (we might not be able to read as many bytes as we want)
    file_io.seek(implied_position_of_eocd_record, IO::SEEK_SET)
    str_containing_eocd_record = file_io.read(MAX_END_OF_CENTRAL_DIRECTORY_RECORD_SIZE)
    eocd_idx_in_buf = locate_eocd_signature(str_containing_eocd_record)

    raise MissingEOCD unless eocd_idx_in_buf

    eocd_offset = implied_position_of_eocd_record + eocd_idx_in_buf
    log do
      'Found EOCD signature at offset %<offset>d' % {offset: eocd_offset}
    end

    eocd_offset
  end

  def all_indices_of_substr_in_str(of_substring, in_string)
    last_i = 0
    found_at_indices = []
    while last_i = in_string.index(of_substring, last_i)
      found_at_indices << last_i
      last_i += of_substring.bytesize
    end
    found_at_indices
  end

  # We have to scan the maximum possible number
  # of bytes that the EOCD can theoretically occupy including the comment after it,
  # and we have to find a combination of:
  #   [EOCD signature, <some ZIP medatata>, comment byte size, comment of size]
  # at the end. To do so, we first find all indices of the signature in the trailer
  # string, and then check whether the bytestring starting at the signature and
  # ending at the end of string satisfies that given pattern.
  def locate_eocd_signature(in_str)
    eocd_signature = 0x06054b50
    eocd_signature_str = [eocd_signature].pack('V')
    unpack_pattern = 'VvvvvVVv'
    minimum_record_size = 22
    str_size = in_str.bytesize
    indices = all_indices_of_substr_in_str(eocd_signature_str, in_str)
    indices.each do |check_at|
      maybe_record = in_str[check_at..str_size]
      # If the record is smaller than the minimum - we will never recover anything
      break if maybe_record.bytesize < minimum_record_size
      # Now we check if the record ends with the combination
      # of the comment size and an arbitrary byte string of that size.
      # If it does - we found our match
      *_unused, comment_size = maybe_record.unpack(unpack_pattern)
      if (maybe_record.bytesize - minimum_record_size) == comment_size
        return check_at # Found the EOCD marker location
      end
    end
    # If we haven't caught anything, return nil deliberately instead of returning the last statement
    nil
  end

  # Find the Zip64 EOCD locator segment offset. Do this by seeking backwards from the
  # EOCD record in the archive by fixed offsets
  #          get_zip64_eocd_location is too high. [15.17/15]
  def get_zip64_eocd_location(file_io, eocd_offset)
    zip64_eocd_loc_offset = eocd_offset
    zip64_eocd_loc_offset -= 4 # The signature
    zip64_eocd_loc_offset -= 4 # Which disk has the Zip64 end of central directory record
    zip64_eocd_loc_offset -= 8 # Offset of the zip64 central directory record
    zip64_eocd_loc_offset -= 4 # Total number of disks

    log do
      'Will look for the Zip64 EOCD locator signature at offset %<offset>d' %
        {offset: zip64_eocd_loc_offset}
    end

    # If the offset is negative there is certainly no Zip64 EOCD locator here
    return unless zip64_eocd_loc_offset >= 0

    file_io.seek(zip64_eocd_loc_offset, IO::SEEK_SET)
    assert_signature(file_io, 0x07064b50)

    log do
      'Found Zip64 EOCD locator at offset %<offset>d' % {offset: zip64_eocd_loc_offset}
    end

    disk_num = read_4b(file_io) # number of the disk
    raise UnsupportedFeature, 'The archive spans multiple disks' if disk_num != 0
    read_8b(file_io)
  rescue ReadError
    nil
  end

  #          num_files_and_central_directory_offset_zip64 is too high. [21.12/15]
  def num_files_and_central_directory_offset_zip64(io, zip64_end_of_cdir_location)
    seek(io, zip64_end_of_cdir_location)

    assert_signature(io, 0x06064b50)

    zip64_eocdr_size = read_8b(io)
    zip64_eocdr = read_n(io, zip64_eocdr_size) # Reading in bulk is cheaper
    zip64_eocdr = StringIO.new(zip64_eocdr)
    skip_ahead_2(zip64_eocdr) # version made by
    skip_ahead_2(zip64_eocdr) # version needed to extract

    disk_n = read_4b(zip64_eocdr) # number of this disk
    disk_n_with_eocdr = read_4b(zip64_eocdr) # number of the disk with the EOCDR
    raise UnsupportedFeature, 'The archive spans multiple disks' if disk_n != disk_n_with_eocdr

    num_files_this_disk = read_8b(zip64_eocdr) # number of files on this disk
    num_files_total     = read_8b(zip64_eocdr) # files total in the central directory

    raise UnsupportedFeature, 'The archive spans multiple disks' if num_files_this_disk != num_files_total

    log do
      'Zip64 EOCD record states there are %<amount>d files in the archive' %
        {amount: num_files_total}
    end

    central_dir_size    = read_8b(zip64_eocdr) # Size of the central directory
    central_dir_offset  = read_8b(zip64_eocdr) # Where the central directory starts

    [num_files_total, central_dir_offset, central_dir_size]
  end

  C_UINT4 = 'V'
  C_UINT2 = 'v'
  C_UINT8 = 'Q<'

  # To prevent too many tiny reads, read the maximum possible size of end of
  # central directory record upfront (all the fixed fields + at most 0xFFFF
  # bytes of the archive comment)
  MAX_END_OF_CENTRAL_DIRECTORY_RECORD_SIZE = 4 + # Offset of the start of central directory
                                             4 + # Size of the central directory
                                             2 + # Number of files in the cdir
                                             4 + # End-of-central-directory signature
                                             2 + # Number of this disk
                                             2 + # Number of disk with the start of cdir
                                             2 + # Number of files in the cdir of this disk
                                             2 + # The comment size
                                             0xFFFF # Maximum comment size

  # To prevent too many tiny reads, read the maximum possible size of the local file header upfront.
  # The maximum size is all the usual items, plus the maximum size
  # of the filename (0xFFFF bytes) and the maximum size of the extras (0xFFFF bytes)
  MAX_LOCAL_HEADER_SIZE = 4 + # signature
                          2 + # Version needed to extract
                          2 + # gp flags
                          2 + # storage mode
                          2 + # dos time
                          2 + # dos date
                          4 + # CRC32
                          4 + # Comp size
                          4 + # Uncomp size
                          2 + # Filename size
                          2 + # Extra fields size
                          0xFFFF + # Maximum filename size
                          0xFFFF   # Maximum extra fields size

  SIZE_OF_USABLE_EOCD_RECORD = 4 + # Signature
                               2 + # Number of this disk
                               2 + # Number of the disk with the EOCD record
                               2 + # Number of entries in the central directory of this disk
                               2 + # Number of entries in the central directory total
                               4 + # Size of the central directory
                               4   # Start of the central directory offset

  def num_files_and_central_directory_offset(file_io, eocd_offset)
    seek(file_io, eocd_offset)

    # The size of the EOCD record is known upfront, so use a strict read
    eocd_record_str = read_n(file_io, SIZE_OF_USABLE_EOCD_RECORD)
    io = StringIO.new(eocd_record_str)

    assert_signature(io, 0x06054b50)
    skip_ahead_2(io) # number_of_this_disk
    skip_ahead_2(io) # number of the disk with the EOCD record
    skip_ahead_2(io) # number of entries in the central directory of this disk
    num_files = read_2b(io)   # number of entries in the central directory total
    cdir_size = read_4b(io)   # size of the central directory
    cdir_offset = read_4b(io) # start of central directorty offset
    [num_files, cdir_offset, cdir_size]
  end

  private_constant :C_UINT4, :C_UINT2, :C_UINT8, :MAX_END_OF_CENTRAL_DIRECTORY_RECORD_SIZE,
                   :MAX_LOCAL_HEADER_SIZE, :SIZE_OF_USABLE_EOCD_RECORD

  # Is provided as a stub to be overridden in a subclass if you need it. Will report
  # during various stages of reading. The log message is contained in the return value
  # of `yield` in the method (the log messages are lazy-evaluated).
  def log
    # The most minimal implementation for the method is just this:
    # $stderr.puts(yield)
  end

  def parse_out_extra_fields(extra_fields_str)
    extra_table = {}
    extras_buf = StringIO.new(extra_fields_str)
    until extras_buf.eof?
      extra_id = read_2b(extras_buf)
      extra_size = read_2b(extras_buf)
      extra_contents = read_n(extras_buf, extra_size)
      extra_table[extra_id] = extra_contents
    end
    extra_table
  end
end
