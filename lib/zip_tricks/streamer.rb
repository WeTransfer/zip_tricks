# Is used to write streamed ZIP archives into the provided IO-ish object.
# The output IO is never going to be rewound or seeked, so the output
# of this object can be coupled directly to, say, a Rack output.
#
# Allows for splicing raw files (for "stored" entries without compression)
# and splicing of deflated files (for "deflated" storage mode).
#
# For stored entries, you need to know the CRC32 (as a uint) and the filesize upfront,
# before the writing of the entry body starts.
#
# Any object that responds to `<<` can be used as the Streamer target - you can use
# a String, an Array, a Socket or a File, at your leisure.
#
# ## Using the Streamer with runtime compression
#
# You can use the Streamer with data descriptors (the CRC32 and the sizes will be
# written after the file data). This allows non-rewinding on-the-fly compression.
# If you are compressing large files, the Deflater object that the Streamer controls
# will be regularly flushed to prevent memory inflation. 
#
#     ZipTricks::Streamer.open(file_socket_or_string) do |zip|
#       zip.write_stored_file('mov.mp4') do |sink|
#         File.open('mov.mp4', 'rb'){|source| IO.copy_stream(source, sink) }
#       end
#       zip.write_deflated_file('long-novel.txt') do |sink|
#         File.open('novel.txt', 'rb'){|source| IO.copy_stream(source, sink) }
#       end
#     end
#
# The central directory will be written automatically at the end of the block.
#
# ## Using the Streamer with entries of known size and having a known CRC32 checksum
#
# Streamer allows "IO splicing" - in this mode it will only control the metadata output,
# but you can write the data to the socket/file outside of the Streamer. For example, when
# using the sendfile gem:
#
#     ZipTricks::Streamer.open(socket) do | zip |
#       zip.add_stored_entry(filename: "myfile1.bin", size: 9090821, crc32: 12485)
#       socket.sendfile(tempfile1)
#       zip.simulate_write(tempfile1.size)
#
#       zip.add_stored_entry(filename: "myfile2.bin", size: 458678, crc32: 89568)
#       socket.sendfile(tempfile2)
#       zip.simulate_write(tempfile2.size)
#     end
#
# Note that you need to use `simulate_write` in this case. This needs to happen since Streamer
# writes absolute offsets into the ZIP (local file header offsets and the like),
# and it relies on the output object to tell it how many bytes have been written
# so far. When using `sendfile` the Ruby write methods get bypassed entirely, and the
# offsets in the IO will not be updated - which will result in an invalid ZIP.
#
# The central directory will be written automatically at the end of the `open` block.
class ZipTricks::Streamer
  require_relative 'streamer/deflated_writer'
  require_relative 'streamer/writable'
  require_relative 'streamer/stored_writer'
  require_relative 'streamer/entry'

  STORED = 0
  DEFLATED = 8

  EntryBodySizeMismatch = Class.new(StandardError)
  InvalidOutput = Class.new(ArgumentError)
  Overflow = Class.new(StandardError)
  UnknownMode = Class.new(StandardError)

  private_constant :DeflatedWriter, :StoredWriter, :STORED, :DEFLATED

  # Creates a new Streamer on top of the given IO-ish object and yields it. Once the given block
  # returns, the Streamer will have it's `close` method called, which will write out the central
  # directory of the archive to the output.
  #
  # @param stream [IO] the destination IO for the ZIP (should respond to `tell` and `<<`)
  # @yield [Streamer] the streamer that can be written to
  def self.open(stream, **kwargs_for_new)
    archive = new(stream, **kwargs_for_new)
    yield(archive)
    archive.close
  end

  # Creates a new Streamer on top of the given IO-ish object.
  #
  # @param stream[IO] the destination IO for the ZIP (should respond to `<<`)
  # @param writer[ZipTricks::ZipWriter] the object to be used as the writer.
  #    Defaults to an instance of ZipTricks::ZipWriter, normally you won't need to override it
  def initialize(stream, writer: create_writer)
    raise InvalidOutput, "The stream must respond to #<<" unless stream.respond_to?(:<<)
    unless stream.respond_to?(:tell) && stream.respond_to?(:advance_position_by)
      stream = ZipTricks::WriteAndTell.new(stream) 
    end

    @out = stream
    @files = []
    @local_header_offsets = []
    @writer = writer
  end

  # Writes a part of a zip entry body (actual binary data of the entry) into the output stream.
  #
  # @param binary_data [String] a String in binary encoding
  # @return self
  def <<(binary_data)
    @out << binary_data
    self
  end

  # Writes a part of a zip entry body (actual binary data of the entry) into the output stream,
  # and returns the number of bytes written. Is implemented to make Streamer usable with
  # `IO.copy_stream(from, to)`.
  #
  # @param binary_data [String] a String in binary encoding
  # @return [Fixnum] the number of bytes written
  def write(binary_data)
    @out << binary_data
    binary_data.bytesize
  end

  # Advances the internal IO pointer to keep the offsets of the ZIP file in check. Use this if you are going
  # to use accelerated writes to the socket (like the `sendfile()` call) after writing the headers, or if you
  # just need to figure out the size of the archive.
  #
  # @param num_bytes [Numeric] how many bytes are going to be written bypassing the Streamer
  # @return [Numeric] position in the output stream / ZIP archive
  def simulate_write(num_bytes)
    @out.advance_position_by(num_bytes)
    @out.tell
  end

  # Writes out the local header for an entry (file in the ZIP) that is using the deflated storage model (is compressed).
  # Once this method is called, the `<<` method has to be called to write the actual contents of the body.
  #
  # Note that the deflated body that is going to be written into the output has to be _precompressed_ (pre-deflated)
  # before writing it into the Streamer, because otherwise it is impossible to know it's size upfront.
  #
  # @param filename [String] the name of the file in the entry
  # @param compressed_size [Fixnum] the size of the compressed entry that is going to be written into the archive
  # @param uncompressed_size [Fixnum] the size of the entry when uncompressed, in bytes
  # @param crc32 [Fixnum] the CRC32 checksum of the entry when uncompressed
  # @return [Fixnum] the offset the output IO is at after writing the entry header
  def add_compressed_entry(filename:, compressed_size:, uncompressed_size:, crc32:)
    add_file_and_write_local_header(filename: filename, crc32: crc32, storage_mode: DEFLATED, 
      compressed_size: compressed_size, uncompressed_size: uncompressed_size)
    @out.tell
  end

  # Writes out the local header for an entry (file in the ZIP) that is using the stored storage model (is stored as-is).
  # Once this method is called, the `<<` method has to be called one or more times to write the actual contents of the body.
  #
  # @param filename [String] the name of the file in the entry
  # @param size [Fixnum] the size of the file when uncompressed, in bytes
  # @param crc32 [Fixnum] the CRC32 checksum of the entry when uncompressed
  # @return [Fixnum] the offset the output IO is at after writing the entry header
  def add_stored_entry(filename:, size:, crc32:)
    add_file_and_write_local_header(filename: filename, crc32: crc32, storage_mode: STORED,
      compressed_size: size, uncompressed_size: size)
    @out.tell
  end

  # Adds an empty directory to the archive with a size of 0 and permissions of 755.
  #
  # @param dirname [String] the name of the directory in the archive
  # @return [Fixnum] the offset the output IO is at after writing the entry header
  def add_empty_directory(dirname:)
    add_file_and_write_local_header(filename: "#{dirname}" + "/", crc32: 0, storage_mode: STORED,
      compressed_size: 0, uncompressed_size: 0)
    @out.tell
  end
  
  # Opens the stream for a stored file in the archive, and yields a writer for that file to the block.
  # Once the write completes, a data descriptor will be written with the actual compressed/uncompressed
  # sizes and the CRC32 checksum.
  #
  # @param filename[String] the name of the file in the archive
  # @yield [#<<, #write] an object that the file contents must be written to
  def write_stored_file(filename)
    add_file_and_write_local_header(filename: filename, storage_mode: STORED,
      use_data_descriptor: true, crc32: 0, compressed_size: 0, uncompressed_size: 0)

    w = StoredWriter.new(@out)
    yield(Writable.new(w))
    crc, comp, uncomp = w.finish

    # Save the information into the entry for when the time comes to write out the central directory
    last_entry = @files[-1]
    last_entry.crc32 = crc
    last_entry.compressed_size = comp
    last_entry.uncompressed_size = uncomp

    @writer.write_data_descriptor(io: @out, crc32: crc, compressed_size: comp, uncompressed_size: uncomp)
  end

  # Opens the stream for a deflated file in the archive, and yields a writer for that file to the block.
  # Once the write completes, a data descriptor will be written with the actual compressed/uncompressed
  # sizes and the CRC32 checksum.
  #
  # @param filename[String] the name of the file in the archive
  # @yield [#<<, #write] an object that the file contents must be written to
  def write_deflated_file(filename)
    add_file_and_write_local_header(filename: filename, storage_mode: DEFLATED,
      use_data_descriptor: true, crc32: 0, compressed_size: 0, uncompressed_size: 0)

    w = DeflatedWriter.new(@out)
    yield(Writable.new(w))
    crc, comp, uncomp = w.finish

    # Save the information into the entry for when the time comes to write out the central directory
    last_entry = @files[-1]
    last_entry.crc32 = crc
    last_entry.compressed_size = comp
    last_entry.uncompressed_size = uncomp
    write_data_descriptor_for_last_entry
  end
    
  # Closes the archive. Writes the central directory, and switches the writer into
  # a state where it can no longer be written to.
  #
  # Once this method is called, the `Streamer` should be discarded (the ZIP archive is complete).
  #
  # @return [Fixnum] the offset the output IO is at after closing the archive
  def close
    # Record the central directory offset, so that it can be written into the EOCD record
    cdir_starts_at = @out.tell

    # Write out the central directory entries, one for each file
    @files.each_with_index do |entry, i|
      header_loc = @local_header_offsets.fetch(i)
      @writer.write_central_directory_file_header(io: @out, local_file_header_location: header_loc,
        gp_flags: entry.gp_flags, storage_mode: entry.storage_mode,
        compressed_size: entry.compressed_size, uncompressed_size: entry.uncompressed_size,
        mtime: entry.mtime, crc32: entry.crc32, filename: entry.filename) #, external_attrs: DEFAULT_EXTERNAL_ATTRS)
    end

    # Record the central directory size, for the EOCDR
    cdir_size = @out.tell - cdir_starts_at

    # Write out the EOCDR
    @writer. write_end_of_central_directory(io: @out, start_of_central_directory_location: cdir_starts_at,
       central_directory_size: cdir_size, num_files_in_archive: @files.length)
    @out.tell
  end

  # Sets up the ZipWriter with wrappers if necessary. The method is called once, when the Streamer
  # gets instantiated - the Writer then gets reused. This method is primarily there so that you
  # can override it.
  #
  # @return [ZipTricks::ZipWriter] the writer to perform writes with
  def create_writer
    ZipTricks::ZipWriter.new
  end

  private

  def add_file_and_write_local_header(filename:, crc32:, storage_mode:, compressed_size:,
      uncompressed_size:, use_data_descriptor: false)

    # Clean backslashes and uniqify filenames if there are duplicates
    filename = remove_backslash(filename)
    filename = uniquify_name(filename) if @files.any? { |e| e.filename == filename }

    raise UnknownMode, "Unknown compression mode #{storage_mode}" unless [STORED, DEFLATED].include?(storage_mode)
    raise Overflow, "Filename is too long" if filename.bytesize > 0xFFFF

    e = Entry.new(filename, crc32, compressed_size, uncompressed_size, storage_mode, mtime=Time.now.utc, use_data_descriptor)
    @files << e
    @local_header_offsets << @out.tell
    @writer.write_local_file_header(io: @out, gp_flags: e.gp_flags, crc32: e.crc32, compressed_size: e.compressed_size,
      uncompressed_size: e.uncompressed_size, mtime: e.mtime, filename: e.filename, storage_mode: e.storage_mode)
  end
      
  def write_data_descriptor_for_last_entry
    e = @files.fetch(-1)
    @writer.write_data_descriptor(io: @out, crc32: 0, compressed_size: e.compressed_size, uncompressed_size: e.uncompressed_size)
  end

  def remove_backslash(filename)
    filename.tr('\\', '_')
  end

  def uniquify_name(filename)
    files = Set.new(@files.map(&:filename))
    copy_pattern = /\((\d+)\)$/ # we add (1), (2), (n) at the end of a filename if there is a duplicate
    parts = filename.split(".")
    ext = if parts.last =~ /gz|zip/ && parts.size > 2
            parts.pop(2)
          elsif parts.size > 1
            parts.pop
          end
    fn_last_part = parts.pop

    duplicate_counter = 1
    loop do
      if fn_last_part =~ copy_pattern
        fn_last_part.sub!(copy_pattern, "(#{duplicate_counter})")
      else
        fn_last_part = "#{fn_last_part} (#{duplicate_counter})"
      end
      new_filename = (parts + [fn_last_part, ext]).compact.join(".")
      return new_filename unless files.include?(new_filename)
      duplicate_counter += 1
    end
  end
end
