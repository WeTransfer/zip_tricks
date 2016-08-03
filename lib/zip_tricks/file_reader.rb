require 'stringio'

module ZipTricks::FileReader
  ReadError = Class.new(StandardError)
  UnsupportedFeature = Class.new(StandardError)
  InvalidStructure = Class.new(ReadError)
  
  class InflatingReader
    def initialize(from_io, compressed_data_size)
      @io = from_io
      @compressed_data_size = compressed_data_size
      @already_read = 0
      @zlib_inflater = ::Zlib::Inflate.new(-Zlib::MAX_WBITS)
    end

    def decompress(n_bytes=nil)
      n_bytes ||= (@compressed_data_size - @already_read)

      return if eof?

      available = @compressed_data_size - @already_read

      return if available.zero?

      n_bytes = available if n_bytes > available

      return '' if n_bytes.zero?

      compressed_chunk = @io.read(n_bytes)
      @already_read += compressed_chunk.bytesize
      @zlib_inflater.inflate(compressed_chunk)
    end

    def eof?
      @zlib_inflater.finished?
    end
  end

  class StoreadReader
    def initialize(from_io, compressed_data_size)
      @io = from_io
      @compressed_data_size = compressed_data_size
      @already_read = 0
    end

    def decompress(n_bytes=nil)
      n_bytes ||= (@compressed_data_size - @already_read)

      return if eof?

      available = @compressed_data_size - @already_read

      return if available.zero?

      n_bytes = available if n_bytes > available

      return '' if n_bytes.zero?

      compressed_chunk = @io.read(n_bytes)
      @already_read += compressed_chunk.bytesize
      compressed_chunk
    end

    def eof?
      @already_read >= @compressed_data_size
    end
  end

  # Represents a file within the ZIP archive being read
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

    # @return [Fixnum] at what offset you should start reading
    #       for the compressed data in your original IO object
    attr_accessor :compressed_data_offset

    # Returns a reader for the actual compressed data of the entry.
    #
    #   reader = entry.reader(source_file)
    #   outfile << reader.decompress(512 * 1024) until reader.eof?
    #
    # @return [InflatingReader] the reader for the data
    def reader(from_io)
      from_io.seek(compressed_data_offset, IO::SEEK_SET)
      case storage_mode
        when 8
          InflatingReader.new(from_io, compressed_size)
        when 0
          StoreadReader.new(from_io, compressed_size)
        else
          raise "Unsupported storage mode for reading (#{storage_mode})"
      end
    end
  end

  # Parse an IO handle to a ZIP archive into an array of Entry objects.
  #
  # @param io[#tell, #seek, #read, #size] an IO-ish object
  # @return [Array<Entry>] an array of entries within the ZIP being parsed
  def self.read_zip_structure(io)
    zip_file_size = io.size
    eocd_offset = get_eocd_offset(io, zip_file_size)

    zip64_end_of_cdir_location = get_zip64_eocd_locator_offset(io, eocd_offset)
    num_files, cdir_location, cdir_size = if zip64_end_of_cdir_location
      num_files_and_central_directory_offset_zip64(io, zip64_end_of_cdir_location)
    else
      num_files_and_central_directory_offset(io, eocd_offset)
    end
    seek(io, cdir_location)

    # Read the entire central directory in one fell swoop
    central_directory_str = read_n(io, cdir_size)
    central_directory_io = StringIO.new(central_directory_str)

    entries = (1..num_files).map { read_cdir_entry(central_directory_io) }
    entries.each do |entry|
      entry.compressed_data_offset = find_compressed_data_start_offset(io, entry.local_file_header_offset)
    end
  end

  private

  def self.skip_ahead_2(io)
    skip_ahead_n(io, 2)
  end

  def self.skip_ahead_4(io)
    skip_ahead_n(io, 4)
  end

  def self.skip_ahead_8(io)
    skip_ahead_n(io, 8)
  end

  def self.seek(io, absolute_pos)
    io.seek(absolute_pos, IO::SEEK_SET)
    raise ReadError, "Expected to seek to #{absolute_pos} but only got to #{io.tell}" unless absolute_pos == io.tell
    nil
  end

  def self.assert_signature(io, signature_magic_number)
    packed = [signature_magic_number].pack(C_V)
    readback = read_4b(io)
    if readback != signature_magic_number
      expected = '0x0' + signature_magic_number.to_s(16)
      actual = '0x0' + readback.to_s(16)
      raise InvalidStructure, "Expected signature #{expected}, but read #{actual}"
    end
  end

  def self.skip_ahead_n(io, n)
    pos_before = io.tell
    io.seek(io.tell + n, IO::SEEK_SET)
    pos_after = io.tell
    delta = pos_after - pos_before
    raise ReadError, "Expected to seek #{n} bytes ahead, but could only seek #{delta} bytes ahead" unless delta == n
    nil
  end

  def self.read_n(io, n_bytes)
    io.read(n_bytes).tap {|d|
      raise ReadError, "Expected to read #{n_bytes} bytes, but the IO was at the end" if d.nil?
      raise ReadError, "Expected to read #{n_bytes} bytes, read #{d.bytesize}" unless d.bytesize == n_bytes
    }
  end

  def self.read_2b(io)
    read_n(io, 2).unpack(C_v).shift
  end

  def self.read_4b(io)
    read_n(io, 4).unpack(C_V).shift
  end

  def self.read_8b(io)
    read_n(io, 8).unpack(C_Qe).shift
  end

  def self.find_compressed_data_start_offset(file_io, local_header_offset)
    seek(file_io, local_header_offset)
    
    # Reading in bulk is cheaper - grab the maximum length of the local header, including
    # any headroom
    local_file_header_str_plus_headroom = file_io.read(MAX_LOCAL_HEADER_SIZE)
    io = StringIO.new(local_file_header_str_plus_headroom)

    assert_signature(io, 0x04034b50)

    # The rest is unreliable, and we have that information from the central directory already.
    # So just skip over it to get at the offset where the compressed data begins
    skip_ahead_2(io) # Version needed to extract
    skip_ahead_2(io) # gp flags
    skip_ahead_2(io) # storage mode
    skip_ahead_2(io) # dos time
    skip_ahead_2(io) # dos date
    skip_ahead_4(io) # CRC32

    skip_ahead_4(io) # Comp size
    skip_ahead_4(io) # Uncomp size

    filename_size = read_2b(io)
    extra_size = read_2b(io)

    skip_ahead_n(io, filename_size)
    skip_ahead_n(io, extra_size)

    local_header_offset + io.tell
  end


  def self.read_cdir_entry(io)
    expected_at = io.tell
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
      extra_table = {}
      extras_buf = StringIO.new(extras)
      until extras_buf.eof? do
        extra_id = read_2b(extras_buf)
        extra_size = read_2b(extras_buf)
        extra_contents = read_n(extras_buf, extra_size)
        extra_table[extra_id] = extra_contents
      end

      # ...of which we really only need the Zip64 extra
      if zip64_extra_contents = extra_table[1] # Zip64 extra
        zip64_extra = StringIO.new(zip64_extra_contents)
        e.uncompressed_size = read_8b(zip64_extra)
        e.compressed_size = read_8b(zip64_extra)
        e.local_file_header_offset = read_8b(zip64_extra)
      end
    end
  end

  def self.get_eocd_offset(file_io, zip_file_size)
    # Start reading from the _comment_ of the zip file (from the very end).
    # The maximum size of the comment is 0xFFFF (what fits in 2 bytes)
    implied_position_of_eocd_record = zip_file_size - MAX_END_OF_CENTRAL_DIRECTORY_RECORD_SIZE
    implied_position_of_eocd_record = 0 if implied_position_of_eocd_record < 0

    # Use a soft seek (we might not be able to get as far behind in the IO as we want)
    # and a soft read (we might not be able to read as many bytes as we want)
    file_io.seek(implied_position_of_eocd_record, IO::SEEK_SET)
    str_containing_eocd_record = file_io.read(MAX_END_OF_CENTRAL_DIRECTORY_RECORD_SIZE)

    # TODO: what to do if multiple occurrences of the signature are found, somehow?
    eocd_sig = [0x06054b50].pack(C_V)
    eocd_idx_in_buf = str_containing_eocd_record.index(eocd_sig)

    raise "Could not find the EOCD signature in the buffer - maybe a malformed ZIP file" unless eocd_idx_in_buf

    implied_position_of_eocd_record + eocd_idx_in_buf
  end

  # Find the Zip64 EOCD locator segment offset. Do this by seeking backwards from the
  # EOCD record in the archive by fixed offsets
  def self.get_zip64_eocd_locator_offset(file_io, eocd_offset)
    zip64_eocd_loc_offset = eocd_offset
    zip64_eocd_loc_offset -= 4 # The signature
    zip64_eocd_loc_offset -= 4 # Which disk has the Zip64 end of central directory record
    zip64_eocd_loc_offset -= 8 # Offset of the zip64 central directory record
    zip64_eocd_loc_offset -= 4 # Total number of disks

    # If the offset is negative there is certainly no Zip64 EOCD locator here
    return unless zip64_eocd_loc_offset >= 0

    file_io.seek(zip64_eocd_loc_offset, IO::SEEK_SET)
    assert_signature(file_io, 0x07064b50)
    disk_num = read_4b(file_io) # number of the disk
    raise UnsupportedFeature, "The archive spans multiple disks" if disk_num != 0
    read_8b(file_io)
  rescue ReadError
    nil
  end

  def self.num_files_and_central_directory_offset_zip64(io, zip64_end_of_cdir_location)
    seek(io, zip64_end_of_cdir_location)
    
    assert_signature(io, 0x06064b50)
    
    zip64_eocdr_size = read_8b(io)
    zip64_eocdr = read_n(io, zip64_eocdr_size) # Reading in bulk is cheaper
    zip64_eocdr = StringIO.new(zip64_eocdr)
    skip_ahead_2(zip64_eocdr) # version made by
    skip_ahead_2(zip64_eocdr) # version needed to extract

    disk_n = read_4b(zip64_eocdr) # number of this disk
    disk_n_with_eocdr = read_4b(zip64_eocdr) # number of the disk with the EOCDR
    raise UnsupportedFeature, "The archive spans multiple disks" if disk_n != disk_n_with_eocdr

    num_files_this_disk = read_8b(zip64_eocdr) # number of files on this disk
    num_files_total     = read_8b(zip64_eocdr) # files total in the central directory

    raise UnsupportedFeature, "The archive spans multiple disks" if num_files_this_disk != num_files_total

    central_dir_size    = read_8b(zip64_eocdr) # Size of the central directory
    central_dir_offset  = read_8b(zip64_eocdr) # Where the central directory starts

    [num_files_total, central_dir_offset, central_dir_size]
  end

  C_V = 'V'.freeze
  C_v = 'v'.freeze
  C_Qe = 'Q<'.freeze

  # To prevent too many tiny reads, read the maximum possible size of end of central directory record
  # upfront (all the fixed fields + at most 0xFFFF bytes of the archive comment)
  MAX_END_OF_CENTRAL_DIRECTORY_RECORD_SIZE = begin
    4 + # Offset of the start of central directory
    4 + # Size of the central directory
    2 + # Number of files in the cdir
    4 + # End-of-central-directory signature
    2 + # Number of this disk
    2 + # Number of disk with the start of cdir
    2 + # Number of files in the cdir of this disk
    2 + # The comment size
    0xFFFF # Maximum comment size
  end

  # To prevent too many tiny reads, read the maximum possible size of the local file header upfront.
  # The maximum size is all the usual items, plus the maximum size
  # of the filename (0xFFFF bytes) and the maximum size of the extras (0xFFFF bytes)
  MAX_LOCAL_HEADER_SIZE =  begin
    4 + # signature
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
  end

  SIZE_OF_USABLE_EOCD_RECORD = begin
    4 + # Signature
    2 + # Number of this disk
    2 + # Number of the disk with the EOCD record
    2 + # Number of entries in the central directory of this disk
    2 + # Number of entries in the central directory total
    4 + # Size of the central directory
    4   # Start of the central directory offset
  end

  def self.num_files_and_central_directory_offset(file_io, eocd_offset)
    seek(file_io, eocd_offset)

    io = StringIO.new(read_n(file_io, SIZE_OF_USABLE_EOCD_RECORD))
    
    assert_signature(io, 0x06054b50)

    skip_ahead_2(io) # number_of_this_disk
    skip_ahead_2(io) # number of the disk with the EOCD record
    skip_ahead_2(io) # number of entries in the central directory of this disk
    num_files = read_2b(io)   # number of entries in the central directory total
    cdir_size = read_4b(io)   # size of the central directory
    cdir_offset = read_4b(io) # start of central directorty offset
    [num_files, cdir_offset, cdir_size]
  end

  private_constant :C_V, :C_v, :C_Qe, :MAX_END_OF_CENTRAL_DIRECTORY_RECORD_SIZE,
    :MAX_LOCAL_HEADER_SIZE, :SIZE_OF_USABLE_EOCD_RECORD
end
