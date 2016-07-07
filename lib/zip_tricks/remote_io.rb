# An object that fakes just-enough of an IO to be dangerous
# - or, more precisely, to be useful as a source for the RubyZip
# central directory parser
class ZipTricks::RemoteIO

  # @param fetcher[#request_object_size, #request_range] an object that can fetch
  def initialize(fetcher = :NOT_SET)
    @pos = 0
    @fetcher = fetcher
    @remote_size = false
  end

  # Emulates IO#seek
  def seek(offset, mode = IO::SEEK_SET)
    case mode
      when IO::SEEK_SET
        @remote_size ||= request_object_size
        @pos = clamp(0, offset, @remote_size)
      when IO::SEEK_END
        @remote_size ||= request_object_size
        @pos = clamp(0, @remote_size + offset, @remote_size)
      else
        raise Errno::ENOTSUP, "Seek mode #{mode.inspect} not supported"
    end
    0 # always return 0!
  end

  # Emulates IO#read
  def read(n_bytes = nil)
    @remote_size ||= request_object_size

    # If the resource is empty there is nothing to read
    return nil if @remote_size.zero?

    maximum_avaialable = @remote_size - @pos
    n_bytes ||= maximum_avaialable # nil == read to the end of file
    raise ArgumentError, "No negative reads(#{n_bytes})" if n_bytes < 0

    n_bytes = clamp(0, n_bytes, maximum_avaialable)

    read_n_bytes_from_remote(@pos, n_bytes).tap do |data|
      if data.bytesize != n_bytes
        raise "Remote read returned #{data.bytesize} bytes instead of #{n_bytes} as requested"
      end
      @pos = clamp(0, @pos + data.bytesize, @remote_size)
    end
  end

  # Returns the current pointer position within the IO.
  # Not used by RubyZip but used in tests of our own
  #
  # @return [Fixnum]
  def pos
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

  def clamp(a,b,c)
    return a if b < a
    return c if b > c
    b
  end
end
