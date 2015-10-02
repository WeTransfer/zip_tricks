class ZipTricks::Streamer
  STATES = [:before_entry, :in_entry_header, :in_entry_body, :in_central_directory, :closed]
  TRANSITIONS = [
    [:before_entry, :in_entry_header],
    [:in_entry_header, :in_entry_body],
    [:in_entry_body, :in_entry_header],
    [:in_entry_body, :in_central_directory],
    [:in_central_directory, :closed]
  ]
  
  def self.open(stream)
    archive = new(stream)
    yield(archive)
    archive.close
  end
  
  def initialize(stream)
    unless stream.respond_to?(:<<) && stream.respond_to?(:tell)
      raise "The stream should respond to #<< and #tell"
    end
    @output_stream = stream
    @entry_set = ::Zip::EntrySet.new
    @state = :before_entry
  end

  def << (binary_data)
    transition_or_maintain! :in_entry_body
    @output_stream << binary_data
  end

  def add_compressed_entry(entry_name, uncompressed_size, crc32, compressed_size)
    transition! :in_entry_header
    
    entry = ::Zip::Entry.new(@file_name, entry_name)
    entry.compression_method = Zip::Entry::DEFLATED
    entry.crc = crc32
    entry.size = uncompressed_size
    entry.compressed_size = compressed_size
    entry.gp_flags = "0000000".to_i(2)
    
    entry.write_local_entry(@output_stream)
    @entry_set << entry
  end

  def add_stored_entry(entry_name, uncompressed_size, crc32)
    transition! :in_entry_header

    entry = ::Zip::Entry.new(@file_name, entry_name)
    entry.compression_method = Zip::Entry::STORED
    entry.crc = crc32
    entry.size = uncompressed_size
    entry.compressed_size = uncompressed_size
    entry.gp_flags = "0000000".to_i(2)
    @entry_set << entry
    entry.write_local_entry(@output_stream)
  end

  def close
    transition! :in_central_directory
    cdir = Zip::CentralDirectory.new(@entry_set, @comment)
    cdir.write_to_stream(@output_stream)
    transition! :closed
  end
  
  private
  
  def transition_or_maintain!(new_state)
    @recorded_transitions ||= []
    return if @state == new_state
    transition!(new_state)
  end
  
  def expect!(state)
    raise "Must be in #{state} state" unless @state == state
  end

  def transition!(new_state)
    @recorded_transitions ||= []
    raise "Unknown state #{new_state}" unless STATES.include?(new_state)
    if TRANSITIONS.include?([@state, new_state])
      @state = new_state
    else
      raise "Cannot change states from #{@state} to #{new_state} (flow: #{@recorded_transitions.inspect})"
    end
  end
end