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
  def initialize(writable, buffer_size, transform = nil)
    @buf = StringIO.new("\0".b * buffer_size)
    @buf.truncate(0)
    @bufsize = buffer_size
    @writable = writable
    @transform = transform || :to_s
    @outbuf = "\0".b * buffer_size
  end

  # Appends the given data to the write buffer, and flushes the buffer into the
  # writable if the buffer size exceeds the `buffer_size` given at initialization
  #
  # @param data[String] data to be written
  # @return self
  def <<(data)
    capacity = @bufsize
    if capacity < 1
      @writable << data.send(@transform)
      return self
    end

    used = @buf.tell
    data = StringIO.new(data)
    data.binmode
    size = data.size
    needed = used + size

    case needed <=> capacity
    when 1 # needed > capacity
      free = capacity - used
      @buf << data.read(free, @outbuf)
      flush
      multiple, remaining = (size - free).divmod(capacity)
      multiple.times do
        @writable << data.read(capacity, @outbuf).send(@transform)
      end
      @buf << data.read(remaining, @outbuf)
    when 0 # needed == capacity
      if used > 0
        @buf << data.string
        flush
      else
        @writable << data.string
      end
    when -1 # needed < capacity
      @buf << data.string
    end
    self
  end

  # Explicitly flushes the buffer if it contains anything
  #
  # @return self
  def flush
    size = @buf.tell
    if size > 0
      @buf.rewind
      @writable << @buf.read(size, @outbuf).send(@transform)
      @buf.rewind
    end
    self
  end

  # Get current size of buffer.
  #
  # @return [Integer] the return value of `buffer#tell`
  def size
    @buf.tell
  end

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
