# frozen_string_literal: true

# Should be included into a Rails controller (together with `ActionController::Live`)
# for easy ZIP output from any action.
module ZipTricks::RailsStreaming
  # Opens a {ZipTricks::Streamer} and yields it to the caller. The output of the streamer
  # gets automatically forwarded to the Rails response stream. When the output completes,
  # the Rails response stream is going to be closed automatically.
  # @param zip_streamer_options[Hash] options that will be passed to the Streamer.
  #     See {ZipTricks::Streamer#initialize} for the full list of options.
  # @yield [Streamer] the streamer that can be written to
  # @return [ZipTricks::OutputEnumerator] The output enumerator assigned to the response body
  def zip_tricks_stream(**zip_streamer_options, &zip_streaming_blk)
    # Set a reasonable content type
    response.headers['Content-Type'] = 'application/zip'
    # Make sure nginx buffering is suppressed - see https://github.com/WeTransfer/zip_tricks/issues/48
    response.headers['X-Accel-Buffering'] = 'no'
    response.sending_file = true
    self.response_body = ZipTricks::OutputEnumerator.new(**zip_streamer_options, &zip_streaming_blk)
  end
end
