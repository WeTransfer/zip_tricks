# frozen_string_literal: true

# An object that fakes just-enough of an IO to be dangerous
# - or, more precisely, to be useful as a source for the FileReader
# central directory parser. Effectively we substitute an IO object
# for an object that fetches parts of the remote file over HTTP using `Range:`
# headers. The `RemoteIO` acts as an adapter between an object that performs the
# actual fetches over HTTP and an object that expects a handful of IO methods to be
# available.
class ZipTricks::RemoteIO
  # @param fetcher[#request_object_size, #request_range] an object that perform fetches
  def initialize(fetcher = :NOT_SET)
    @pos = 0
    @fetcher = fetcher
    @remote_size = false
  end

  # Emulates IO#seek
  def seek(offset, mode = IO::SEEK_SET)
    raise "Unsupported read mode #{mode}" unless mode == IO::SEEK_SET
    @remote_size ||= request_object_size
    @pos = clamp(0, offset, @remote_size)
    0 # always return 0!
  end

  # Emulates IO#size.
  #
  # @return [Fixnum] the size of the remote resource
  def size
    @remote_size ||= request_object_size
  end

  # Emulates IO#read, but requires the number of bytes to read
  # The read will be limited to the
  # size of the remote resource relative to the current offset in the IO,
  # so if you are at offset 0 in the IO of size 10, doing a `read(20)`
  # will only return you 10 bytes of result, and not raise any exceptions.
  #
  # @param n_bytes[Fixnum, nil] how many bytes to read, or `nil` to read all the way to the end
  # @return [String] the read bytes
  # Rubocop: convention: Assignment Branch Condition size for read is too high. [17.92/15]
  # Rubocop: convention: Method has too many lines. [13/10]
  def read(n_bytes = nil)
    @remote_size ||= request_object_size

    # If the resource is empty there is nothing to read
    return nil if @remote_size.zero?

    maximum_avaialable = @remote_size - @pos
    n_bytes ||= maximum_avaialable # nil == read to the end of file
    return '' if n_bytes.zero?
    raise ArgumentError, "No negative reads(#{n_bytes})" if n_bytes < 0

    n_bytes = clamp(0, n_bytes, maximum_avaialable)

    read_n_bytes_from_remote(@pos, n_bytes).tap do |data|
      if data.bytesize != n_bytes
        raise "Remote read returned #{data.bytesize} bytes instead of #{n_bytes} as requested"
      end
      @pos = clamp(0, @pos + data.bytesize, @remote_size)
    end
  end

  # Returns the current pointer position within the IO
  #
  # @return [Fixnum]
  def tell
    @pos
  end

  protected

  def request_range(range)
    @fetcher.request_range(range)
  end

  def request_object_size
    @fetcher.request_object_size
  end

  # Reads N bytes at offset from remote
  def read_n_bytes_from_remote(start_at, n_bytes)
    range = (start_at..(start_at + n_bytes - 1))
    request_range(range)
  end

  # Reads the Content-Length and caches it
  def remote_size
    @remote_size ||= request_object_size
  end

  private

  def clamp(a, b, c)
    return a if b < a
    return c if b > c
    b
  end
end
