# frozen_string_literal: true

# The output enumerator makes it possible to "pull" from a ZipTricks streamer
# object instead of having it "push" writes to you. It will "stash" the block which
# writes the ZIP archive through the streamer, and when you call `each` on the Enumerator
# it will yield you the bytes the block writes. Since it is an enumerator you can
# use `next` to take chunks written by the ZipTricks streamer one by one. It can be very
# convenient when you need to segment your ZIP output into bigger chunks for, say,
# uploading them to a cloud storage provider such as S3.
#
# Another use of the output enumerator is outputting a ZIP archive from Rails or Rack,
# where an object responding to `each` is required which yields Strings. For instance,
# you can return a ZIP archive from Rack like so:
#
#     iterable_zip_body = ZipTricks::OutputEnumerator.new do | streamer |
#       streamer.write_deflated_file('big.csv') do |sink|
#         CSV(sink) do |csv_writer|
#           csv_writer << Person.column_names
#           Person.all.find_each do |person|
#             csv_writer << person.attributes.values
#           end
#         end
#       end
#     end
#
#     [200, {'Content-Type' => 'binary/octet-stream'}, iterable_zip_body]
class ZipTricks::OutputEnumerator
  DEFAULT_WRITE_BUFFER_SIZE = 64 * 1024
  # Creates a new OutputEnumerator.
  #
  # @param streamer_options[Hash] options for Streamer, see {ZipTricks::Streamer.new}
  # @param write_buffer_size[Integer] By default all ZipTricks writes are unbuffered. For output to sockets
  #     it is beneficial to bulkify those writes so that they are roughly sized to a socket buffer chunk. This
  #     object will bulkify writes for you in this way (so `each` will yield not on every call to `<<` from the Streamer
  #     but at block size boundaries or greater). Set it to 0 for unbuffered writes.
  # @param blk a block that will receive the Streamer object when executing. The block will not be executed
  #     immediately but only once `each` is called on the OutputEnumerator
  def initialize(write_buffer_size: DEFAULT_WRITE_BUFFER_SIZE, **streamer_options, &blk)
    @streamer_options = streamer_options.to_h
    @bufsize = write_buffer_size.to_i
    @archiving_block = blk
  end

  # Executes the block given to the constructor with a {ZipTricks::Streamer}
  # and passes each written chunk to the block given to the method. This allows one
  # to "take" output of the ZIP piecewise. If called without a block will return an Enumerator
  # that you can pull data from using `next`.
  #
  # **NOTE** Because the `WriteBuffer` inside this object can reuse the buffer, it is important
  #    that the `String` that is yielded **either** gets consumed eagerly (written byte-by-byte somewhere, or `#dup`-ed)
  #    since the write buffer will clear it after your block returns. If you expand this Enumerator
  #    eagerly into an Array you might notice that a lot of the segments of your ZIP output are
  #    empty - this means that you need to duplicate them.
  #
  # @yield [String] a chunk of the ZIP output in binary encoding
  def each
    if block_given?
      block_write = ZipTricks::BlockWrite.new { |chunk| yield(chunk) }
      buffer = ZipTricks::WriteBuffer.new(block_write, @bufsize)
      ZipTricks::Streamer.open(buffer, **@streamer_options, &@archiving_block)
      buffer.flush
    else
      enum_for(:each)
    end
  end
end
