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
  # @param writable[#<<] An object that responds to `#<<` with a String as argument
  # @param buffer_size[Integer] How many bytes to buffer
  def initialize(writable, buffer_size)
    @buf = StringIO.new
    @buf.binmode
    @buffer_size = buffer_size
    @writable = writable
  end

  # Appends the given data to the write buffer, and flushes the buffer into the
  # writable if the buffer size exceeds the `buffer_size` given at initialization
  #
  # @param data[String] data to be written
  # @return self
  def <<(data)
    data = data.to_s
    size = data.bytesize
    capacity = @buffer_size
    if capacity < 1
      @writable << data
    elsif size > 0
      used = @buf.size
      if used > 0 && used + size >= capacity
        if size % capacity != 0
          free = capacity - used
          size -= free
          @buf << data.byteslice(0, free)
          data = data.byteslice(free, size)
        end
        flush
      end
      case size <=> capacity
      when -1 # size < capacity
        @buf << data
      when 0 # size == capacity
        @writable << data
      when 1 # size > capacity
        remaining = size % capacity
        if remaining > 0
          size -= remaining
          @buf << data.byteslice(size, remaining)
          data = data.byteslice(0, size)
        end
        @writable << data
      end
    end
    self
  end

  # Explicitly flushes the buffer if it contains anything
  #
  # @return self
  def flush
    if @buf.size > 0
      # A StringIO internally contains one String which it mutates in place.
      # When the buffer is local this is not a problem, but if this string leaks
      # to the outside of the object it might be possible that it gets referenced
      # from elsewhere and, unexpectedly for the caller, will become an empty string...
      @writable << @buf.string.dup
      @buf.truncate(0) # ...because we truncate it before doing the next writes
      @buf.rewind
    end
    self
  end

  alias_method :flush!, :flush

  # Flushes the buffer and returns the result of `#to_i` of the contained `writable`.
  # Primarily facilitates working with StreamCRC32 objects where you finish the
  # computation by retrieving the CRC as an integer
  #
  # @return [Integer] the return value of `writable#to_i`
  def to_i
    flush
    @writable.to_i
  end
end
