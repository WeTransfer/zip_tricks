module ZipTricks::RailsStreaming
  def zip_tricks_stream
    response.headers['Content-Type'] = 'application/zip'
    # Create a wrapper for the write call that quacks like something you
    # can << to, used by ZipTricks
    w = ZipTricks::BlockWrite.new { |chunk| response.stream.write(chunk) }
    ZipTricks::Streamer.open(w){|z| yield(z) }
  ensure
    response.stream.close
  end
end
