# frozen_string_literal: true

# Some operations (such as CRC32) benefit when they are performed
# on larger chunks of data. In certain use cases, it is possible that
# the consumer of ZipTricks is going to be writing small chunks
# in rapid succession, so CRC32 is going to have to perform a lot of
# CRC32 combine operations - and this adds up. Since the CRC32 value
# is usually not needed until the complete output has completed
# we can buffer at least some amount of data before computing CRC32 over it.
class ZipTricks::WriteBuffer
  # Creates a new WriteBuffer bypassing into a given writable object
  #
  # @param writable[#<<] An object that responds to `#<<` with string as argument
  # @param buffer_size[Integer] How many bytes to buffer
  def initialize(writable, buffer_size)
    @buf = StringIO.new
    @buffer_size = buffer_size
    @writable = writable
  end

  # Appends the given data to the write buffer, and flushes the buffer into the
  # writable if the buffer size exceeds the `buffer_size` given at initialization
  #
  # @param data[String] data to be written
  # @return self
  def <<(data)
    @buf << data
    flush! if @buf.size > @buffer_size
    self
  end

  # Explicitly flushes the buffer if it contains anything
  #
  # @return self
  def flush!
    @writable << @buf.string if @buf.size > 0
    @buf.truncate(0)
    @buf.rewind
    self
  end

  # Flushes the buffer and returns the result of `#to_i` of the contained `writable`.
  # Primarily facilitates working with StreamCRC32 objects where you finish the
  # computation by retrieving the CRC as an integer
  #
  # @return [Integer] the return value of `writable#to_i`
  def to_i
    flush!
    @writable.to_i
  end
end
