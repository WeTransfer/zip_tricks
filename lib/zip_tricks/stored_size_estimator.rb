# Helps to estimate archive sizes
class ZipTricks::StoredSizeEstimator < Struct.new(:manifest)

  # Performs the estimate using fake archiving. It needs to know the sizes of the
  # entries upfront. Usage:
  #
  #     expected_zip_size = StoredSizeEstimator.perform_fake_archiving do | estimator |
  #       estimator.add_stored_entry("file.doc", size=898291)
  #       estimator.add_compressed_entry("family.tif", size=89281911, compressed_size=121908)
  #     end
  #
  # @return [Fixnum] the size of the resulting archive, in bytes
  # @yield [StoredSizeEstimator] the estimator
  def self.perform_fake_archiving
    _, bytes = ZipTricks::Manifest.build do |manifest|
      # The API for this class uses positional arguments. The Manifest API
      # uses keyword arguments.
      call_adapter = new(manifest)
      yield(call_adapter)
    end
    bytes
  end

  # Add a fake entry to the archive, to see how big it is going to be in the end.
  #
  # @param name [String] the name of the file (filenames are variable-width in the ZIP)
  # @param size_uncompressed [Fixnum] size of the uncompressed entry
  # @return self
  def add_stored_entry(name, size_uncompressed)
    manifest.add_stored_entry(name: name, size_uncompressed: size_uncompressed)
    self
  end

  # Add a fake entry to the archive, to see how big it is going to be in the end.
  #
  # @param name [String] the name of the file (filenames are variable-width in the ZIP)
  # @param size_uncompressed [Fixnum] size of the uncompressed entry
  # @param size_compressed [Fixnum] size of the compressed entry
  # @return self
  def add_compressed_entry(name, size_uncompressed, size_compressed)
    manifest.add_compressed_entry(name: name, size_uncompressed: size_uncompressed, size_compressed: size_compressed)
    self
  end
end
