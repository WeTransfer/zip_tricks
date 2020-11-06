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
#         CSV(sink) do |csv_write|
#           csv << Person.column_names
#           Person.all.find_each do |person|
#             csv << person.attributes.values
#           end
#         end
#       end
#     end
#
#     [200, {'Content-Type' => 'binary/octet-stream'}, iterable_zip_body]
class ZipTricks::OutputEnumerator
  # Creates a new OutputEnumerator.
  #
  # @param streamer_options[Hash] options for Streamer, see {ZipTricks::Streamer.new}
  #     It might be beneficial to tweak the `write_buffer_size` to your liking so that you won't be
  #     doing too many write attempts and block right after
  # @param blk a block that will receive the Streamer object when executing. The block will not be executed
  #     immediately but only once `each` is called on the OutputEnumerator
  def initialize(**streamer_options, &blk)
    @streamer_options = streamer_options.to_h
    @archiving_block = blk
  end

  # Executes the block given to the constructor with a {ZipTricks::Streamer}
  # and passes each written chunk to the block given to the method. This allows one
  # to "take" output of the ZIP piecewise. If called without a block will return an Enumerator
  # that you can pull data from using `next`.
  #
  # @yield [String] a chunk of the ZIP output in binary encoding
  def each
    if block_given?
      block_write = ZipTricks::BlockWrite.new { |chunk| yield(chunk) }
      ZipTricks::Streamer.open(block_write, **@streamer_options, &@archiving_block)
    else
      enum_for(:each)
    end
  end
end
