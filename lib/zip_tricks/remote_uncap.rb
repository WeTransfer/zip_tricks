# Alows reading the central directory of a remote ZIP file without
# downloading the entire file. The central directory provides the
# offsets at which the actual file contents is located. You can then
# use the `Range:` HTTP headers to download those entries separately.
class ZipTricks::RemoteUncap

  # Represents a file embedded within a remote ZIP archive
  class RemoteZipEntry

    # @return [String] filename of the file in the remote ZIP
    attr_accessor :name

    # @return [Fixnum] size in bytes of the file when uncompressed
    attr_accessor :size_uncompressed

    # @return [Fixnum] size in bytes of the file when compressed (the segment in the ZIP)
    attr_accessor :size_compressed

    # @return [Fixnum] compression method (0 for stored, 8 for deflate)
    attr_accessor :compression_method

    # @return [Fixnum] where the file data starts within the ZIP
    attr_accessor :starts_at_offset

    # @return [Fixnum] where the file data ends within the zip.
    #     Will be equal to starts_at_offset if the file is empty
    attr_accessor :ends_at_offset

    # Yields the object during initialization
    def initialize
      yield self
    end
  end

  # @param uri[String] the HTTP(S) URL to read the ZIP footer from 
  # @return [Array<RemoteZipEntry>] metadata about the files within the remote archive
  def self.files_within_zip_at(uri)
    fetcher = new(uri)
    fake_io = ZipTricks::RemoteIO.new(fetcher)
    entries = ZipTricks.const_get(:FileReader).read_zip_structure(fake_io)
    entries.map do | remote_entry |
      RemoteZipEntry.new do | entry |
        entry.name               = remote_entry.filename
        entry.starts_at_offset   = remote_entry.compressed_data_offset
        entry.size_uncompressed  = remote_entry.uncompressed_size
        entry.size_compressed    = remote_entry.compressed_size
        entry.compression_method = remote_entry.storage_mode
      end
    end
  end

  def initialize(uri)
    @uri = URI(uri)
  end

  # @param range[Range] the HTTP range of data to fetch from remote
  # @return [String] the response body of the ranged request
  def request_range(range)
    request = Net::HTTP::Get.new(@uri)
    request.range = range
    http = Net::HTTP.start(@uri.hostname, @uri.port)
    http.request(request).body
  end

  # @return [Fixnum] the byte size of the ranged request
  def request_object_size
    http = Net::HTTP.start(@uri.hostname, @uri.port)
    http.request_head(uri)['Content-Length'].to_i
  end
end
