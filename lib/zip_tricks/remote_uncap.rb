# frozen_string_literal: true

# Alows reading the central directory of a remote ZIP file without
# downloading the entire file. The central directory provides the
# offsets at which the actual file contents is located. You can then
# use the `Range:` HTTP headers to download those entries separately.
#
# Please read the security warning in `FileReader` _VERY CAREFULLY_
# before you use this module.
module ZipTricks::RemoteUncap
  # @param uri[String] the HTTP(S) URL to read the ZIP footer from
  # @param reader_class[Class] which class to use for reading
  # @param options_for_zip_reader[Hash] any additional options to give to
  # {ZipTricks::FileReader} when reading
  # @return [Array<ZipTricks::FileReader::ZipEntry>] metadata about the
  # files within the remote archive
  def self.files_within_zip_at(uri, reader_class: ZipTricks::FileReader, **options_for_zip_reader)
    fake_io = ZipTricks::RemoteIO.new(uri)
    reader = reader_class.new
    reader.read_zip_structure(io: fake_io, **options_for_zip_reader)
  end
end
