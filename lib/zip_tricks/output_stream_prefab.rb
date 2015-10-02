# A ZipOutputStream that never rewinds output, and can be used for splicing files
# verbatim into the output _if you know their size and CRC32_.
# It does not perform compression, and does not use local footers - so you can
# compute the size it is going to have using a pretty accurate "fake archiving" procedure.
class ZipTricks::OutputStreamPrefab < ::Zip::OutputStream
  # Create the parent class, but set our own output handle as the @output_stream destination
  # @param [io] The IO object that will receive the streamed ZIP. Can be any non-rewindable IO.
  # @param [stream_flag] Works like the one in Rubyzip, but is ignored
  # @param [encrypter] Works like the one in Rubyzip, but is ignored
  def initialize(io, stream_flag=false, encrypter=nil)
    super StringIO.new, stream_flag=true, encrypter=nil
    # replace the instantiated output stream with our stub
    @output_stream = io
  end

  # Adds a new entry.
  # 
  # @param [entry_name] The filename of the entry
  # @param [size] The size of the uncompressed file
  # @param [crc] The CRC32 of the entry that is going to be written
  def put_next_entry(entry_name, size, crc, deflated_size=nil)
    new_entry = ::Zip::Entry.new(@file_name, entry_name)
    compression_used = deflated_size ? Zip::Entry::DEFLATED : Zip::Entry::STORED
    new_entry.compression_method = compression_used
    
    # Since we know the CRC and the size upfront we do not need local footers the way zipline uses them.
    # Instead we can generate the header when starting the entry, and never touch it afterwards.
    # Just set them from the method arguments.
    new_entry.crc, new_entry.size = crc, size
    
    # Moved here from finalize_current_entry (since all the information is already available).
    # Should be the size of the entry (actually byte for byte the contents of the raw file,
    # since there will be no compression) plus the size of the local header for the entry. Easy.
    new_entry.compressed_size = size + new_entry.calculate_local_header_size
    
    # The super method signature is
    # put_next_entry(name_or_object, comment = nil, extra = nil, 
    # compression_method = Entry::DEFLATED, level = Zip.default_compression)
    # If we want not to buffer, we have to force it to switch into the passthrough compressor.
    # Otherwise we only receive the compressed blob in one go once the Compressor object gets a finish() call
    # and dumps it's compressed data. Probably we _could_ do a deflate compression in a streaming fashion if we could
    # write a Compressor class that performs deflate compression on a per-block basis.
    # This also calls entry.write_local_entry(@output_stream) which flushes the local header.
    super(new_entry, nil, nil, new_entry.compression_method)
    
    # The original comments in zipline said that uncompressed size in the local file header must be zero when bit 3
    # of the general purpose flags is set, so it set the size after the header has been written.
    # This is not really relevant for us though because we are not using local footers.
    # new_entry.size = size
  end
  
  # We never need to update local headers, because we set all the data in the header ahead of time.
  # And this is the method that tries to rewind the IO, so fuse it out and turn it into a no-op.
  def update_local_headers
    nil
  end
  
  # Always force the passthru compressor (even if we have compressed entries they are already deflated).
  def get_compressor(entry, level)
    ::Zip::PassThruCompressor.new(@output_stream)
  end
  
  # Overridden - the @compressor writes using this method, so an override can be used to trace
  # how often the compressor calls the method and whether it buffers or not. If Zip::DEFLATE is used
  # for entry compression this method will be called once per file with a HUUUUGE Ruby string.
  def <<(data)
    super
  end
end
