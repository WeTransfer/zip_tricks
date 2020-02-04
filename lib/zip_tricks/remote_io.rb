# frozen_string_literal: true

# An object that fakes just-enough of an IO to be dangerous
# - or, more precisely, to be useful as a source for the FileReader
# central directory parser. Effectively we substitute an IO object
# for an object that fetches parts of the remote file over HTTP using `Range:`
# headers. The `RemoteIO` acts as an adapter between an object that performs the
# actual fetches over HTTP and an object that expects a handful of IO methods to be
# available.
class ZipTricks::RemoteIO
  # @param url[String, URI] the HTTP/HTTPS URL of the object to be retrieved
  def initialize(url)
    @pos = 0
    @uri = URI(url)
    @remote_size = nil
  end

  # Emulates IO#seek
  # @param offset[Integer] absolute offset in the remote resource to seek to
  # @param mode[Integer] The seek mode (only SEEK_SET is supported)
  def seek(offset, mode = IO::SEEK_SET)
    raise "Unsupported read mode #{mode}" unless mode == IO::SEEK_SET
    @remote_size ||= request_object_size
    @pos = clamp(0, offset, @remote_size)
    0 # always return 0!
  end

  # Emulates IO#size.
  #
  # @return [Integer] the size of the remote resource
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
  def read(n_bytes = nil)
    # If the resource is empty there is nothing to read
    return if size.zero?

    maximum_avaialable = size - @pos
    n_bytes ||= maximum_avaialable # nil == read to the end of file
    return '' if n_bytes.zero?
    raise ArgumentError, "No negative reads(#{n_bytes})" if n_bytes < 0

    n_bytes = clamp(0, n_bytes, maximum_avaialable)

    http_range = (@pos..(@pos + n_bytes - 1))
    request_range(http_range).tap do |data|
      raise "Remote read returned #{data.bytesize} bytes instead of #{n_bytes} as requested" if data.bytesize != n_bytes
      @pos = clamp(0, @pos + data.bytesize, size)
    end
  end

  # Returns the current pointer position within the IO
  #
  # @return [Fixnum]
  def tell
    @pos
  end

  protected

  # Only used internally when reading the remote ZIP.
  #
  # @param range[Range] the HTTP range of data to fetch from remote
  # @return [String] the response body of the ranged request
  def request_range(range)
    http = Net::HTTP.start(@uri.hostname, @uri.port)
    request = Net::HTTP::Get.new(@uri)
    request.range = range
    response = http.request(request)
    case response.code
    when "206", "200"
      response.body
    else
      raise "Remote at #{@uri} replied with code #{response.code}"
    end
  end

  # For working with S3 it is a better idea to perform a GET request for one byte, since doing a HEAD
  # request needs a different permission - and standard GET presigned URLs are not allowed to perform it
  #
  # @return [Integer] the size of the remote resource, parsed either from Content-Length or Content-Range header
  def request_object_size
    http = Net::HTTP.start(@uri.hostname, @uri.port)
    request = Net::HTTP::Get.new(@uri)
    request.range = 0..0
    response = http.request(request)
    case response.code
    when "206"
      content_range_header_value = response['Content-Range']
      content_range_header_value.split('/').last.to_i
    when "200"
      response['Content-Length'].to_i
    else
      raise "Remote at #{@uri} replied with code #{response.code}"
    end
  end

  private

  def clamp(a, b, c)
    return a if b < a
    return c if b > c
    b
  end
end
