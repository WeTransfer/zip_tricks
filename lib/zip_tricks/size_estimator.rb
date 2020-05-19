# frozen_string_literal: true

# Helps to estimate archive sizes
class ZipTricks::SizeEstimator
  require_relative 'streamer'

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
  #       estimator.add_deflated_entry(filename: "family.tif",
  #               uncompressed_size: 89281911, compressed_size: 121908)
  #     end
  #
  # @param kwargs_for_streamer_new Any options to pass to Streamer, see {Streamer#initialize}
  # @return [Integer] the size of the resulting archive, in bytes
  # @yield [SizeEstimator] the estimator
  def self.estimate(**kwargs_for_streamer_new)
    streamer = ZipTricks::Streamer.new(ZipTricks::NullWriter, **kwargs_for_streamer_new)
    estimator = new(streamer)
    yield(estimator)
    streamer.close # Returns the .tell of the contained IO
  end

  # Add a fake entry to the archive, to see how big it is going to be in the end.
  #
  # @param filename [String] the name of the file (filenames are variable-width in the ZIP)
  # @param size [Fixnum] size of the uncompressed entry
  # @param use_data_descriptor[Boolean] whether the entry uses a postfix
  # data descriptor to specify size
  # @return self
  def add_stored_entry(filename:, size:, use_data_descriptor: false)
    @streamer.add_stored_entry(filename: filename,
                               crc32: 0,
                               size: size,
                               use_data_descriptor: use_data_descriptor)
    @streamer.simulate_write(size)
    if use_data_descriptor
      @streamer.update_last_entry_and_write_data_descriptor(crc32: 0, compressed_size: size, uncompressed_size: size)
    end
    self
  end

  # Add a fake entry to the archive, to see how big it is going to be in the end.
  #
  # @param filename [String] the name of the file (filenames are variable-width in the ZIP)
  # @param uncompressed_size [Fixnum] size of the uncompressed entry
  # @param compressed_size [Fixnum] size of the compressed entry
  # @param use_data_descriptor[Boolean] whether the entry uses a postfix data
  #                                     descriptor to specify size
  # @return self
  def add_deflated_entry(filename:, uncompressed_size:, compressed_size:, use_data_descriptor: false)
    @streamer.add_deflated_entry(filename: filename,
                                 crc32: 0,
                                 compressed_size: compressed_size,
                                 uncompressed_size: uncompressed_size,
                                 use_data_descriptor: use_data_descriptor)

    @streamer.simulate_write(compressed_size)
    if use_data_descriptor
      @streamer.update_last_entry_and_write_data_descriptor(crc32: 0,
                                                            compressed_size: compressed_size,
                                                            uncompressed_size: uncompressed_size)
    end
    self
  end

  # Add an empty directory to the archive.
  #
  # @param dirname [String] the name of the directory
  # @return self
  def add_empty_directory_entry(dirname:)
    @streamer.add_empty_directory(dirname: dirname)
    self
  end
end
