# frozen_string_literal: true

# Can be used as a Rack response body directly. Will yield
# a {ZipTricks::Streamer} for adding entries to the archive and writing
# zip entry bodies.
class ZipTricks::OutputEnumerator
  # Prepares a new Rack response body with a Zip output stream.
  # The block given to the constructor will be called when the response
  # body will be read by the webserver, and will receive a {ZipTricks::Streamer}
  # as it's block argument. You can then add entries to the Streamer as usual.
  # The archive will be automatically closed at the end of the block.
  #
  #     # Precompute the Content-Length ahead of time
  #     content_length = ZipTricks::SizeEstimator.estimate do | estimator |
  #       estimator.add_stored_entry(filename: 'large.tif', size: 1289894)
  #     end
  #
  #     # Prepare the response body. 
  #     # The block will only be called when the
  #     # response starts to be written.
  #     body = ZipTricks::OutputEnumerator.new do | streamer |
  #       streamer.add_stored_entry(filename: 'large.tif', size: 1289894, crc32: 198210)
  #       streamer << large_file.read(1024*1024) until large_file.eof?
  #       ...
  #     end
  #
  #     return [200, {'Content-Type' => 'binary/octet-stream',
  #     'Content-Length' => content_length.to_s}, body]
  def initialize(**streamer_options, &blk)
    @streamer_options = streamer_options.to_h
    @archiving_block = blk
  end

  # Executes the block given to the constructor with a {ZipTricks::Streamer}
  # and passes each written chunk to the block given to the method. This allows one
  # to "take" output of the ZIP piecewise.
  def each
    if block_given?
      block_write = ZipTricks::BlockWrite.new {|chunk| yield(chunk) }
      ZipTricks::Streamer.open(block_write, **@streamer_options, &@archiving_block)
    else
      enum_for(:each)
    end
  end
end
