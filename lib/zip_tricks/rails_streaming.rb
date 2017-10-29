# frozen_string_literal: true

# Should be included into a Rails controller (together with `ActionController::Live`)
# for easy ZIP output from any action.
module ZipTricks::RailsStreaming
  # Opens a {ZipTricks::Streamer} and yields it to the caller. The output of the streamer
  # gets automatically forwarded to the Rails response stream. When the output completes,
  # the Rails response stream is going to be closed automatically.
  # @yield [Streamer] the streamer that can be written to
  def zip_tricks_stream
    response.headers['Content-Type'] = 'application/zip'
    # Create a wrapper for the write call that quacks like something you
    # can << to, used by ZipTricks
    w = ZipTricks::BlockWrite.new { |chunk| response.stream.write(chunk) }
    ZipTricks::Streamer.open(w) { |z| yield(z) }
  ensure
    response.stream.close
  end
end
