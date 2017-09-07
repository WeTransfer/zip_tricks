# Gets yielded from the writing methods of the CompressingStreamer
# and accepts the data being written into the ZIP
class ZipTricks::Streamer::Writable

  # Initializes a new Writable with the object it delegates the writes to.
  # Normally you would not need to use this method directly
  def initialize(writer)
    @writer = writer
  end
  # Writes the given data to the output stream
  #
  # @param d[String] the binary string to write (part of the uncompressed file)
  # @return [self]
  def <<(d) 
    @writer << d 
    self 
  end
  
  # Writes the given data to the output stream
  #
  # @param d[String] the binary string to write (part of the uncompressed file)
  # @return [Fixnum] the number of bytes written
  def write(d) 
    @writer << d
    d.bytesize
  end
end
