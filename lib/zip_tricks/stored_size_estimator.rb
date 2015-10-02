class ZipTricks::StoredSizeEstimator < Struct.new(:zip)
  # One meg of fake data. Has an overridden inspect()
  # so that it does not fill the inspecting terminal with garbage.
  ONE_MEGABYTE = Class.new(String) do
    def inspect
      "<Fake blob(#{bytesize} bytes)>"
    end
  end.new('A' * (1024 * 1024)).freeze
  FAKE_CRC = Zlib.crc32('Mary had a little lamb')
  NO_OP_BYTES_RECEIVER = ->(bytes) {}
  
  # Performs the estimate using fake archiving. It needs to know the sizes of the
  # entries upfront. Usage:
  #
  #  expected_zip_size = StoredSizeEstimator.perform_fake_archiving do | estimator |
  #    estimator.add_entry("file.doc", size=898291)
  #    estimator.add_entry("family.JPG", size=89281911)
  #  end
  #
  # @return []
  # @yield [StoredSizeEstimator] the estimator
  def self.perform_fake_archiving
    output_io = ::ZipTricks::BlockWrite.new(&NO_OP_BYTES_RECEIVER)
    ::ZipTricks::OutputStreamPrefab.open(output_io) do | zip |
      yield(new(zip))
    end
    output_io.tell
  end
  
  # Add a fake entry to the archive, to see how big it is going to be in the end.
  #
  # @param name[String] - the name of the file (filenames are variable-width in the ZIP)
  # @param size[Fixnum] - size of the uncompressed or compressed entry (size of the data that will be appended to the ZIP)
  # @return self
  def add_stored_entry(name, size_uncompressed)
    zip.put_next_stored_entry(name, size_uncompressed, FAKE_CRC)
    write_fake_data(zip, size_uncompressed)
    self
  end
  
  # Add a fake entry to the archive, to see how big it is going to be in the end.
  #
  # @param name[String] - the name of the file (filenames are variable-width in the ZIP)
  # @param size[Fixnum] - size of the uncompressed or compressed entry (size of the data that will be appended to the ZIP)
  # @return self
  def add_compressed_entry(name, size_uncompressed, size_compressed)
    zip.put_next_compressed_entry(name, size_uncompressed, FAKE_CRC, size_compressed)
    write_fake_data(zip, size_compressed)
    self
  end
  
  private
  # To send "fake data" to the zip compressor without creating too many strings, or having too much
  # memory pressure, we use a trick. We know that the entry we are going to be archiving is X bytes.
  # Split it in parts of 1 Mb or less.
  # Then, if a part is exactly 1 meg, "write" a string constant we preallocated earlier.
  # This will prevent Ruby from generating ANY extra strings in the process, except for the very last one
  def write_fake_data(zip, n_bytes)
    whole_blobs = n_bytes / ONE_MEGABYTE.bytesize
    partial_blob_size = n_bytes % ONE_MEGABYTE.bytesize
    whole_blobs.times { zip << ONE_MEGABYTE }
    zip << ONE_MEGABYTE[0...partial_blob_size] if partial_blob_size.nonzero?
  end
end
