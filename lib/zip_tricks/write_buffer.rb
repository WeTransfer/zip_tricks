# frozen_string_literal: true

# Some operations (such as CRC32) benefit when they are performed
# on larger chunks of data. In certain use cases, it is possible that
# the consumer of ZipTricks is going to be writing small chunks
# in rapid succession, so CRC32 is going to have to perform a lot of
# CRC32 combine operations - and this adds up. Since the CRC32 value
# is usually not needed until the complete output has completed
# we can buffer at least some amount of data before computing CRC32 over it.
# We also use this buffer for output via Rack, where some amount of buffering
# helps reduce the number of syscalls made by the webserver. ZipTricks performs
# lots of very small writes, and some degree of speedup (about 20%) can be achieved
# with a buffer of a few KB.
#
# Note that there is no guarantee that the write buffer is going to flush at or above
# the given `buffer_size`, because for writes which exceed the buffer size it will
# first `flush` and then write through the oversized chunk, without buffering it. This
# helps conserve memory. Also note that the buffer will *not* duplicate strings for you
# and *will* yield the same buffer String over and over, so if you are storing it in an
# Array you might need to duplicate it.
#
# Note also that the WriteBuffer assumes that the object it `<<`-writes into is going
# to **consume** in some way the string that it passes in. After the `<<` method returns,
# the WriteBuffer will be cleared, and it passes the same String reference on every call
# to `<<`. Therefore, if you need to retain the output of the WriteBuffer in, say, an Array,
# you might need to `.dup` the `String` it gives you.
class ZipTricks::WriteBuffer
  # Creates a new WriteBuffer bypassing into a given writable object
  #
  # @param writable[#<<] An object that responds to `#<<` with a String as argument
  # @param buffer_size[Integer] How many bytes to buffer
  def initialize(writable, buffer_size)
    # Allocating the buffer using a zero-padded String as a variation
    # on using capacity:, which JRuby apparently does not like very much. The
    # desire here is that the buffer doesn't have to be resized during the lifetime
    # of the object.
    @buf = ("\0".b * (buffer_size * 2)).clear
    @buffer_size = buffer_size
    @writable = writable
  end

  # Appends the given data to the write buffer, and flushes the buffer into the
  # writable if the buffer size exceeds the `buffer_size` given at initialization
  #
  # @param data[String] data to be written
  # @return self
  def <<(data)
    if data.bytesize >= @buffer_size
      flush unless @buf.empty? # <- this is were we can output less than @buffer_size
      @writable << data
    else
      @buf << data
      flush if @buf.bytesize >= @buffer_size
    end
    self
  end

  # Explicitly flushes the buffer if it contains anything
  #
  # @return self
  def flush
    unless @buf.empty?
      @writable << @buf
      @buf.clear
    end
    self
  end

  # `flush!` was renamed to `flush` but we preserve this method for backwards compatibility
  alias_method :flush!, :flush
end
