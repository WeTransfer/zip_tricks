# frozen_string_literal: true

require 'set'

# Is used to write streamed ZIP archives into the provided IO-ish object.
# The output IO is never going to be rewound or seeked, so the output
# of this object can be coupled directly to, say, a Rack output. The
# output can also be a String, Array or anything that responds to `<<`.
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
#
# ## On-the-fly deflate -using the Streamer with async/suspended writes and data descriptors
#
# If you are unable to use the block versions of `write_deflated_file` and `write_stored_file`
# there is an option to use a separate writer object. It gets returned from `write_deflated_file`
# and `write_stored_file` if you do not provide them with a block, and will accept data writes.
#
#     ZipTricks::Streamer.open(socket) do | zip |
#       w = zip.write_stored_file('mov.mp4')
#       w << data
#       w.close
#     end
#
# The central directory will be written automatically at the end of the `open` block. If you need
# to manage the Streamer manually, or defer the central directory write until appropriate, use
# the constructor instead and call `Streamer#close`:
#
#     zip = ZipTricks::Streamer.new(out_io)
#     .....
#     zip.close
#
# Calling {Streamer#close} **will not** call `#close` on the underlying IO object.
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
  OffsetOutOfSync = Class.new(StandardError)

  private_constant :STORED, :DEFLATED

  # Creates a new Streamer on top of the given IO-ish object and yields it. Once the given block
  # returns, the Streamer will have it's `close` method called, which will write out the central
  # directory of the archive to the output.
  #
  # @param stream [IO] the destination IO for the ZIP (should respond to `tell` and `<<`)
  # @param kwargs_for_new [Hash] keyword arguments for {Streamer.new}
  # @yield [Streamer] the streamer that can be written to
  def self.open(stream, **kwargs_for_new)
    archive = new(stream, **kwargs_for_new)
    yield(archive)
    archive.close
  end

  # Creates a new Streamer that writes to a buffer. The buffer can be read from using `each`,
  # and the creation of the ZIP is in lockstep with the caller calling `each` on the returned
  # output enumerator object. This can be used when the calling program wants to stream the
  # output of the ZIP archive and throttle that output, or split it into chunks, or use it
  # as a generator.
  #
  # For example:
  #
  #     # The block given to {output_enum} won't be executed immediately - rather it
  #     # will only start to execute when the caller starts to read from the output
  #     # by calling `each`
  #     body = ZipTricks::Streamer.output_enum(writer: CustomWriter) do |zip|
  #       streamer.add_stored_entry(filename: 'large.tif', size: 1289894, crc32: 198210)
  #       streamer << large_file.read(1024*1024) until large_file.eof?
  #       ...
  #     end
  #
  #     body.each do |bin_string|
  #       # Send the output somewhere, buffer it in a file etc.
  #       ...
  #     end
  #
  # @param kwargs_for_new [Hash] keyword arguments for {Streamer.new}
  # @return [ZipTricks::OutputEnumerator] the enumerator you can read bytestrings of the ZIP from by calling `each`
  def self.output_enum(**kwargs_for_new, &zip_streamer_block)
    ZipTricks::OutputEnumerator.new(**kwargs_for_new, &zip_streamer_block)
  end

  # Creates a new Streamer on top of the given IO-ish object.
  #
  # @param writable[#<<] the destination IO for the ZIP. Anything that responds to `<<` can be used.
  # @param writer[ZipTricks::ZipWriter] the object to be used as the writer.
  #    Defaults to an instance of ZipTricks::ZipWriter, normally you won't need to override it
  # @param auto_rename_duplicate_filenames[Boolean] whether duplicate filenames, when encountered,
  #    should be suffixed with (1), (2) etc. Default value is `false` - if
  #    dupliate names are used an exception will be raised
  def initialize(writable, writer: create_writer, auto_rename_duplicate_filenames: false)
    raise InvalidOutput, 'The writable must respond to #<< or #write' unless writable.respond_to?(:<<) || writable.respond_to?(:write)

    @out = ZipTricks::WriteAndTell.new(writable)
    @files = []
    @path_set = ZipTricks::PathSet.new
    @writer = writer
    @dedupe_filenames = auto_rename_duplicate_filenames
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
  # @return [Integer] the number of bytes written
  def write(binary_data)
    @out << binary_data
    binary_data.bytesize
  end

  # Advances the internal IO pointer to keep the offsets of the ZIP file in
  # check. Use this if you are going to use accelerated writes to the socket
  # (like the `sendfile()` call) after writing the headers, or if you
  # just need to figure out the size of the archive.
  #
  # @param num_bytes [Integer] how many bytes are going to be written bypassing the Streamer
  # @return [Integer] position in the output stream / ZIP archive
  def simulate_write(num_bytes)
    @out.advance_position_by(num_bytes)
    @out.tell
  end

  # Writes out the local header for an entry (file in the ZIP) that is using
  # the deflated storage model (is compressed). Once this method is called,
  # the `<<` method has to be called to write the actual contents of the body.
  #
  # Note that the deflated body that is going to be written into the output
  # has to be _precompressed_ (pre-deflated) before writing it into the
  # Streamer, because otherwise it is impossible to know it's size upfront.
  #
  # @param filename [String] the name of the file in the entry
  # @param modification_time [Time] the modification time of the file in the archive
  # @param compressed_size [Integer] the size of the compressed entry that
  #                                   is going to be written into the archive
  # @param uncompressed_size [Integer] the size of the entry when uncompressed, in bytes
  # @param crc32 [Integer] the CRC32 checksum of the entry when uncompressed
  # @param use_data_descriptor [Boolean] whether the entry body will be followed by a data descriptor
  # @param unix_permissions[Fixnum?] which UNIX permissions to set, normally the default should be used
  # @return [Integer] the offset the output IO is at after writing the entry header
  def add_deflated_entry(filename:, modification_time: Time.now.utc, compressed_size: 0, uncompressed_size: 0, crc32: 0, unix_permissions: nil, use_data_descriptor: false)
    add_file_and_write_local_header(filename: filename,
                                    modification_time: modification_time,
                                    crc32: crc32,
                                    storage_mode: DEFLATED,
                                    compressed_size: compressed_size,
                                    uncompressed_size: uncompressed_size,
                                    unix_permissions: unix_permissions,
                                    use_data_descriptor: use_data_descriptor)
    @out.tell
  end

  # Writes out the local header for an entry (file in the ZIP) that is using
  # the stored storage model (is stored as-is).
  # Once this method is called, the `<<` method has to be called one or more
  # times to write the actual contents of the body.
  #
  # @param filename [String] the name of the file in the entry
  # @param modification_time [Time] the modification time of the file in the archive
  # @param size [Integer] the size of the file when uncompressed, in bytes
  # @param crc32 [Integer] the CRC32 checksum of the entry when uncompressed
  # @param use_data_descriptor [Boolean] whether the entry body will be followed by a data descriptor. When in use
  # @param unix_permissions[Fixnum?] which UNIX permissions to set, normally the default should be used
  # @return [Integer] the offset the output IO is at after writing the entry header
  def add_stored_entry(filename:, modification_time: Time.now.utc,  size: 0, crc32: 0, unix_permissions: nil, use_data_descriptor: false)
    add_file_and_write_local_header(filename: filename,
                                    modification_time: modification_time,
                                    crc32: crc32,
                                    storage_mode: STORED,
                                    compressed_size: size,
                                    uncompressed_size: size,
                                    unix_permissions: unix_permissions,
                                    use_data_descriptor: use_data_descriptor)
    @out.tell
  end

  # Adds an empty directory to the archive with a size of 0 and permissions of 755.
  #
  # @param dirname [String] the name of the directory in the archive
  # @param modification_time [Time] the modification time of the directory in the archive
  # @param unix_permissions[Fixnum?] which UNIX permissions to set, normally the default should be used
  # @return [Integer] the offset the output IO is at after writing the entry header
  def add_empty_directory(dirname:, modification_time: Time.now.utc, unix_permissions: nil)
    add_file_and_write_local_header(filename: dirname.to_s + '/',
                                    modification_time: modification_time,
                                    crc32: 0,
                                    storage_mode: STORED,
                                    compressed_size: 0,
                                    uncompressed_size: 0,
                                    unix_permissions: unix_permissions,
                                    use_data_descriptor: false)
    @out.tell
  end

  # Opens the stream for a stored file in the archive, and yields a writer
  # for that file to the block.
  # Once the write completes, a data descriptor will be written with the
  # actual compressed/uncompressed sizes and the CRC32 checksum.
  #
  # Using a block, the write will be terminated with a data descriptor outright.
  #
  #     zip.write_stored_file("foo.txt") do |sink|
  #       IO.copy_stream(source_file, sink)
  #     end
  #
  # If deferred writes are desired (for example - to integrate with an API that
  # does not support blocks, or to work with non-blocking environments) the method
  # has to be called without a block. In that case it returns the sink instead,
  # permitting to write to it in a deferred fashion. When `close` is called on
  # the sink, any remanining compression output will be flushed and the data
  # descriptor is going to be written.
  #
  # Note that even though it does not have to happen within the same call stack,
  # call sequencing still must be observed. It is therefore not possible to do
  # this:
  #
  #     writer_for_file1 = zip.write_stored_file("somefile.jpg")
  #     writer_for_file2 = zip.write_stored_file("another.tif")
  #     writer_for_file1 << data
  #     writer_for_file2 << data
  #
  # because it is likely to result in an invalid ZIP file structure later on.
  # So using this facility in async scenarios is certainly possible, but care
  # and attention is recommended.
  #
  # @param filename[String] the name of the file in the archive
  # @param modification_time [Time] the modification time of the file in the archive
  # @param unix_permissions[Fixnum?] which UNIX permissions to set, normally the default should be used
  # @yield [#<<, #write] an object that the file contents must be written to that will be automatically closed
  # @return [#<<, #write, #close] an object that the file contents must be written to, has to be closed manually
  def write_stored_file(filename, modification_time: Time.now.utc, unix_permissions: nil)
    add_stored_entry(filename: filename,
                     modification_time: modification_time,
                     use_data_descriptor: true,
                     crc32: 0,
                     size: 0,
                     unix_permissions: unix_permissions)

    writable = Writable.new(self, StoredWriter.new(@out))
    if block_given?
      yield(writable)
      writable.close
    end
    writable
  end

  # Opens the stream for a deflated file in the archive, and yields a writer
  # for that file to the block. Once the write completes, a data descriptor
  # will be written with the actual compressed/uncompressed sizes and the
  # CRC32 checksum.
  #
  # Using a block, the write will be terminated with a data descriptor outright.
  #
  #     zip.write_stored_file("foo.txt") do |sink|
  #       IO.copy_stream(source_file, sink)
  #     end
  #
  # If deferred writes are desired (for example - to integrate with an API that
  # does not support blocks, or to work with non-blocking environments) the method
  # has to be called without a block. In that case it returns the sink instead,
  # permitting to write to it in a deferred fashion. When `close` is called on
  # the sink, any remanining compression output will be flushed and the data
  # descriptor is going to be written.
  #
  # Note that even though it does not have to happen within the same call stack,
  # call sequencing still must be observed. It is therefore not possible to do
  # this:
  #
  #     writer_for_file1 = zip.write_deflated_file("somefile.jpg")
  #     writer_for_file2 = zip.write_deflated_file("another.tif")
  #     writer_for_file1 << data
  #     writer_for_file2 << data
  #     writer_for_file1.close
  #     writer_for_file2.close
  #
  # because it is likely to result in an invalid ZIP file structure later on.
  # So using this facility in async scenarios is certainly possible, but care
  # and attention is recommended.
  #
  # @param filename[String] the name of the file in the archive
  # @param modification_time [Time] the modification time of the file in the archive
  # @param unix_permissions[Fixnum?] which UNIX permissions to set, normally the default should be used
  # @yield [#<<, #write] an object that the file contents must be written to
  def write_deflated_file(filename, modification_time: Time.now.utc, unix_permissions: nil)
    add_deflated_entry(filename: filename,
                       modification_time: modification_time,
                       use_data_descriptor: true,
                       crc32: 0,
                       compressed_size: 0,
                       uncompressed_size: 0,
                       unix_permissions: unix_permissions)

    writable = Writable.new(self, DeflatedWriter.new(@out))
    if block_given?
      yield(writable)
      writable.close
    end
    writable
  end

  # Closes the archive. Writes the central directory, and switches the writer into
  # a state where it can no longer be written to.
  #
  # Once this method is called, the `Streamer` should be discarded (the ZIP archive is complete).
  #
  # @return [Integer] the offset the output IO is at after closing the archive
  def close
    # Make sure offsets are in order
    verify_offsets!

    # Record the central directory offset, so that it can be written into the EOCD record
    cdir_starts_at = @out.tell

    # Write out the central directory entries, one for each file
    @files.each do |entry|
      @writer.write_central_directory_file_header(io: @out,
                                                  local_file_header_location: entry.local_header_offset,
                                                  gp_flags: entry.gp_flags,
                                                  storage_mode: entry.storage_mode,
                                                  compressed_size: entry.compressed_size,
                                                  uncompressed_size: entry.uncompressed_size,
                                                  mtime: entry.mtime,
                                                  crc32: entry.crc32,
                                                  filename: entry.filename,
                                                  unix_permissions: entry.unix_permissions)
    end

    # Record the central directory size, for the EOCDR
    cdir_size = @out.tell - cdir_starts_at

    # Write out the EOCDR
    @writer.write_end_of_central_directory(io: @out,
                                           start_of_central_directory_location: cdir_starts_at,
                                           central_directory_size: cdir_size,
                                           num_files_in_archive: @files.length)

    # Clear the files so that GC will not have to trace all the way to here to deallocate them
    @files.clear
    @path_set.clear

    # and return the final offset
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

  # Updates the last entry written with the CRC32 checksum and compressed/uncompressed
  # sizes. For stored entries, `compressed_size` and `uncompressed_size` are the same.
  # After updating the entry will immediately write the data descriptor bytes
  # to the output.
  #
  # @param crc32 [Integer] the CRC32 checksum of the entry when uncompressed
  # @param compressed_size [Integer] the size of the compressed segment within the ZIP
  # @param uncompressed_size [Integer] the size of the entry once uncompressed
  # @return [Integer] the offset the output IO is at after writing the data descriptor
  def update_last_entry_and_write_data_descriptor(crc32:, compressed_size:, uncompressed_size:)
    # Save the information into the entry for when the time comes to write
    # out the central directory
    last_entry = @files.fetch(-1)
    last_entry.crc32 = crc32
    last_entry.compressed_size = compressed_size
    last_entry.uncompressed_size = uncompressed_size

    offset_before_data_descriptor = @out.tell
    @writer.write_data_descriptor(io: @out,
                                  crc32: last_entry.crc32,
                                  compressed_size: last_entry.compressed_size,
                                  uncompressed_size: last_entry.uncompressed_size)
    last_entry.bytes_used_for_data_descriptor = @out.tell - offset_before_data_descriptor

    @out.tell
  end

  private

  def verify_offsets!
    # We need to check whether the offsets noted for the entries actually make sense
    computed_offset = @files.map(&:total_bytes_used).inject(0, &:+)
    actual_offset = @out.tell
    if computed_offset != actual_offset
      message = <<-EMS
The offset of the Streamer output IO is out of sync with the expected value. All entries written so far,
including their compressed bodies, local headers and data descriptors, add up to a certain offset,
but this offset does not match the actual offset of the IO.

Entries add up to #{computed_offset} bytes and the IO is at #{actual_offset} bytes.

This can happen if you write local headers for an entry, write the "body" of the entry directly to the IO
object which is your destination, but do not adjust the offset known to the Streamer object. To adjust
the offfset you need to call `Streamer#simulate_write(body_size)` after outputting the entry. Otherwise
the local header offsets of the entries you write are going to be incorrect and some ZIP applications
are going to have problems opening your archive.
EMS
      raise OffsetOutOfSync, message
    end
  end

  def add_file_and_write_local_header(
      filename:,
      modification_time:,
      crc32:,
      storage_mode:,
      compressed_size:,
      uncompressed_size:,
      use_data_descriptor:,
      unix_permissions:)

    # Clean backslashes
    filename = remove_backslash(filename)
    raise UnknownMode, "Unknown compression mode #{storage_mode}" unless [STORED, DEFLATED].include?(storage_mode)
    raise Overflow, 'Filename is too long' if filename.bytesize > 0xFFFF

    # If we need to massage filenames to enforce uniqueness,
    # do so before we check for file/directory conflicts
    filename = ZipTricks::UniquifyFilename.call(filename, @path_set) if @dedupe_filenames

    # Make sure there is no file/directory clobbering (conflicts), or - if deduping is disabled -
    # no duplicate filenames/paths
    if filename.end_with?('/')
      @path_set.add_directory_path(filename)
    else
      @path_set.add_file_path(filename)
    end

    if use_data_descriptor
      crc32 = 0
      compressed_size = 0
      uncompressed_size = 0
    end

    local_header_starts_at = @out.tell

    e = Entry.new(filename,
                  crc32,
                  compressed_size,
                  uncompressed_size,
                  storage_mode,
                  modification_time,
                  use_data_descriptor,
                  _local_file_header_offset = local_header_starts_at,
                  _bytes_used_for_local_header = 0,
                  _bytes_used_for_data_descriptor = 0,
                  unix_permissions)

    @writer.write_local_file_header(io: @out,
                                    gp_flags: e.gp_flags,
                                    crc32: e.crc32,
                                    compressed_size: e.compressed_size,
                                    uncompressed_size: e.uncompressed_size,
                                    mtime: e.mtime,
                                    filename: e.filename,
                                    storage_mode: e.storage_mode)
    e.bytes_used_for_local_header = @out.tell - e.local_header_offset

    @files << e
  end

  def remove_backslash(filename)
    filename.tr('\\', '_')
  end
end
