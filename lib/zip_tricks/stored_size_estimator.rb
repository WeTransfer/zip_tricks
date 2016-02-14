# Helps to estimate archive sizes
class ZipTricks::StoredSizeEstimator < Struct.new(:zip_streamer)
  # One meg of fake data. Has an overridden inspect()
  # so that it does not fill the inspecting terminal with garbage.
  FAKE_CRC = Zlib.crc32('Mary had a little lamb')
  NO_OP_BYTES_RECEIVER = ->(bytes) {}
  
  NullWriter = Class.new do
    def <<(data); self; end
  end.new
  
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
    output_io = ZipTricks::WriteAndTell.new(NullWriter)
    ZipTricks::Streamer.open(output_io) do | zip_streamer |
      yield(new(zip_streamer))
    end
    output_io.tell
  end
  
  # Add a fake entry to the archive, to see how big it is going to be in the end.
  #
  # @param name [String] the name of the file (filenames are variable-width in the ZIP)
  # @param size_uncompressed [Fixnum] size of the uncompressed entry
  # @return self
  def add_stored_entry(name, size_uncompressed)
    zip_streamer.add_stored_entry(name, size_uncompressed, FAKE_CRC)
    zip_streamer.simulate_write(size_uncompressed)
    self
  end
  
  # Add a fake entry to the archive, to see how big it is going to be in the end.
  #
  # @param name [String] the name of the file (filenames are variable-width in the ZIP)
  # @param size_uncompressed [Fixnum] size of the uncompressed entry
  # @param size_compressed [Fixnum] size of the compressed entry
  # @return self
  def add_compressed_entry(name, size_uncompressed, size_compressed)
    zip_streamer.add_compressed_entry(name, size_uncompressed, FAKE_CRC, size_compressed)
    zip_streamer.simulate_write(size_compressed)
    self
  end
end
