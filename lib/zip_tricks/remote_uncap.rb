# frozen_string_literal: true

# Alows reading the central directory of a remote ZIP file without
# downloading the entire file. The central directory provides the
# offsets at which the actual file contents is located. You can then
# use the `Range:` HTTP headers to download those entries separately.
#
# Please read the security warning in `FileReader` _VERY CAREFULLY_
# before you use this module.
class ZipTricks::RemoteUncap
  # @param uri[String] the HTTP(S) URL to read the ZIP footer from
  # @param reader_class[Class] which class to use for reading
  # @param options_for_zip_reader[Hash] any additional options to give to
  # {ZipTricks::FileReader} when reading
  # @return [Array<ZipTricks::FileReader::ZipEntry>] metadata about the
  # files within the remote archive
  def self.files_within_zip_at(uri,
                               reader_class: ZipTricks::FileReader,
                               **options_for_zip_reader)
    fetcher = new(uri)
    fake_io = ZipTricks::RemoteIO.new(fetcher)
    reader = reader_class.new
    reader.read_zip_structure(io: fake_io, **options_for_zip_reader)
  end

  def initialize(uri)
    @uri = URI(uri)
  end

  # Only used internally when reading the remote ZIP.
  #
  # @param range[Range] the HTTP range of data to fetch from remote
  # @return [String] the response body of the ranged request
  def request_range(range)
    request = Net::HTTP::Get.new(@uri)
    request.range = range
    http = Net::HTTP.start(@uri.hostname, @uri.port)
    http.request(request).body
  end

  # Only used internally when reading the remote ZIP.
  #
  # @return [Fixnum] the byte size of the ranged request
  def request_object_size
    http = Net::HTTP.start(@uri.hostname, @uri.port)
    http.request_head(uri)['Content-Length'].to_i
  end
end
