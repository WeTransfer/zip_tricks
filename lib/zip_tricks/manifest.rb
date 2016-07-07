# Helps to estimate archive sizes
class ZipTricks::Manifest < Struct.new(:zip_streamer, :io, :part_list)

  # Describes a span within the ZIP bytestream
  class ZipSpan < Struct.new(:part_type, :byte_range_in_zip, :filename, :additional_metadata)
  end

  # Builds an array of spans within the ZIP file and computes the size of the resulting archive in bytes.
  #
  #     zip_spans, bytesize = Manifest.build do | b |
  #       b.add_stored_entry(name: "file.doc", size: 898291)
  #       b.add_compressed_entry(name: "family.tif", size: 89281911, compressed_size: 121908)
  #     end
  #     bytesize #=> ... (Fixnum or Bignum)
  #     zip_spans[0] #=> Manifest::ZipSpan(part_type: :entry_header, byte_range_in_zip: 0..44, ...)
  #     zip_spans[-1] #=> Manifest::ZipSpan(part_type: :central_directory, byte_range_in_zip: 776721..898921, ...)
  #
  # @return [Array<ZipSpan>, Fixnum] an array of byte spans within the final ZIP, and the total size of the archive
  # @yield [Manifest] the manifest object you can add entries to
  def self.build
    output_io = ZipTricks::WriteAndTell.new(ZipTricks::NullWriter)
    part_list = []
    last_range_end = 0
    ZipTricks::Streamer.open(output_io) do | zip_streamer |
      manifest = new(zip_streamer, output_io, part_list)
      yield(manifest)
      last_range_end = part_list[-1].byte_range_in_zip.end
    end

    # Record the position of the central directory
    directory_location = (last_range_end + 1)..(output_io.tell - 1)
    part_list << ZipSpan.new(:central_directory, directory_location, :central_directory, nil)

    [part_list, output_io.tell]
  end

  # Add a fake entry to the archive, to see how big it is going to be in the end.
  #
  # @param name [String] the name of the file (filenames are variable-width in the ZIP)
  # @param size_uncompressed [Fixnum] size of the uncompressed entry
  # @param segment_info[Object] if you need to save anything to retrieve later from the Manifest,
  #                            pass it here (like the URL of the file)
  # @return self
  def add_stored_entry(name:, size_uncompressed:, segment_info: nil)
    register_part(:entry_header, name, segment_info) do
      zip_streamer.add_stored_entry(name, size_uncompressed, C_fake_crc)
    end

    register_part(:entry_body, name, segment_info) do
      zip_streamer.simulate_write(size_uncompressed)
    end

    self
  end

  # Add a fake entry to the archive, to see how big it is going to be in the end.
  #
  # @param name [String] the name of the file (filenames are variable-width in the ZIP)
  # @param size_uncompressed [Fixnum] size of the uncompressed entry
  # @param size_compressed [Fixnum] size of the compressed entry
  # @param segment_info[Object] if you need to save anything to retrieve later from the Manifest,
  #                            pass it here (like the URL of the file)
  # @return self
  def add_compressed_entry(name:, size_uncompressed:, size_compressed:, segment_info: nil)
    register_part(:entry_header, name, segment_info) do
      zip_streamer.add_compressed_entry(name, size_uncompressed, C_fake_crc, size_compressed)
    end

    register_part(:entry_body, name, segment_info) do
      zip_streamer.simulate_write(size_compressed)
    end

    self
  end

  private

  C_fake_crc = Zlib.crc32('Mary had a little lamb')
  private_constant :C_fake_crc

  def register_part(span_type, filename, metadata)
    before, _, after = io.tell, yield, (io.tell - 1)
    part_list << ZipSpan.new(span_type, (before..after), filename, metadata)
  end
end
