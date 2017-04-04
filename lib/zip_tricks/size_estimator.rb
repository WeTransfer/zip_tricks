# Helps to estimate archive sizes
class ZipTricks::SizeEstimator
  require_relative 'streamer'
  
  # Used to mark a couple of methods public
  class DetailStreamer < ::ZipTricks::Streamer
    public :add_file_and_write_local_header, :write_data_descriptor_for_last_entry
  end
  private_constant :DetailStreamer
  
  # Creates a new estimator with a Streamer object. Normally you should use
  # `estimate` instead an not use this method directly.
  def initialize(streamer)
    @streamer = streamer
  end
  private :initialize
  
  # Performs the estimate using fake archiving. It needs to know the sizes of the
  # entries upfront. Usage:
  #
  #     expected_zip_size = SizeEstimator.estimate do | estimator |
  #       estimator.add_stored_entry(filename: "file.doc", size: 898291)
  #       estimator.add_compressed_entry(filename: "family.tif", uncompressed_size: 89281911, compressed_size: 121908)
  #     end
  #
  # @return [Fixnum] the size of the resulting archive, in bytes
  # @yield [SizeEstimator] the estimator
  def self.estimate
    output_io = ZipTricks::WriteAndTell.new(ZipTricks::NullWriter)
    DetailStreamer.open(output_io) { |zip| yield(new(zip)) }
    output_io.tell
  end

  # Add a fake entry to the archive, to see how big it is going to be in the end.
  #
  # @param filename [String] the name of the file (filenames are variable-width in the ZIP)
  # @param size [Fixnum] size of the uncompressed entry
  # @param use_data_descriptor[Boolean] whether the entry uses a postfix data descriptor to specify size
  # @return self
  def add_stored_entry(filename:, size:, use_data_descriptor: false)
    udd = !!use_data_descriptor
    @streamer.add_file_and_write_local_header(filename: filename, crc32: 0, storage_mode: 0,
      compressed_size: size, uncompressed_size: size, use_data_descriptor: udd)
    @streamer.simulate_write(size)
    @streamer.write_data_descriptor_for_last_entry if udd
    self
  end

  # Add a fake entry to the archive, to see how big it is going to be in the end.
  #
  # @param filename [String] the name of the file (filenames are variable-width in the ZIP)
  # @param uncompressed_size [Fixnum] size of the uncompressed entry
  # @param compressed_size [Fixnum] size of the compressed entry
  # @param use_data_descriptor[Boolean] whether the entry uses a postfix data descriptor to specify size
  # @return self
  def add_compressed_entry(filename:, uncompressed_size:, compressed_size:, use_data_descriptor: false)
    udd = !!use_data_descriptor
    @streamer.add_file_and_write_local_header(filename: filename, crc32: 0, storage_mode: 8,
      compressed_size: compressed_size, uncompressed_size: uncompressed_size, use_data_descriptor: udd)
    @streamer.simulate_write(compressed_size)
    @streamer.write_data_descriptor_for_last_entry if udd
    self
  end
  
  # Add an empty directory to the archive.
  #
  # @param dirname [String] the name of the directory
  # @return self
  def add_empty_directory_entry(dirname:)
    @streamer.add_file_and_write_local_header(filename: "#{dirname}" + "/", crc32: 0, storage_mode: 8,
      compressed_size: 0, uncompressed_size: 0)
    self
  end
end
