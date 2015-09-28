# Stashes a block given by the Rack webserver when calling each() on a body, and calls
# that block every time it is written to using :<< (shovel). Poses as an IO for rubyzip.
class ZipTricks::BlockWrite
  # The block is the block given to each() of the Rack body.
  def initialize(&block)
    @block = block
    @pos = 0
  end

  # The zip library needs to get the position in the IO, and it does so using tell().
  def tell
    @pos
  end
  
  # Make sure those methods raise outright
  [:seek, :pos=, :to_s].each do |m|
    define_method(m) do |*args|
      raise "#{m} not supported - this IO adapter is non-rewindable"
    end
  end

  # Every time this object gets written to, call the Rack body each() block with the bytes given instead.
  def <<(buf)
    return if buf.nil?
    return if buf.bytesize.zero? # Zero-size output has a special meaning when using chunked encoding
    encoded = buf.force_encoding(Encoding::BINARY) # Make sure the output is binary
    @pos += encoded.bytesize
    @block.call(encoded)
  end
  
  def close
    nil
  end
end
