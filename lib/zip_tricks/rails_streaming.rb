# frozen_string_literal: true

# Should be included into a Rails controller for easy ZIP output from any action. Note that the stream will
# be a Rails "Live" streaming response, and will potentially be executed in a different thread than your
# controller code - so things such as ActiveSupport::Current might not be working the way you expect.
# When configuring an upstream proxy, make sure keepalive is enabled in nginx, as per this
# StackOverflow response: https://stackoverflow.com/a/22429224
module ZipTricks::RailsStreaming

  def self.included(into_controller)
    # send_stream is only available via ActionController::Live - Rails does not provide
    # unbuffered outputs without it due to how ActionController works. We don't want to have the
    # entirety of Rails in our tests so we only include it if it is defined.
    into_controller.include(ActionController::Live) if defined?(ActionController::Live)
    super
  end

  # Opens a {ZipTricks::Streamer} and yields it to the caller. The output of the streamer
  # gets automatically forwarded to the Rails response stream. When the output completes,
  # the Rails response stream is going to be closed automatically.
  # @param zip_streamer_options[Hash] options that will be passed to the Streamer.
  #     See {ZipTricks::Streamer#initialize} for the full list of options.
  # @param filename[String] the name of the downloaded file
  # @param type[String] the MIME type of the downloaded file (some ZIP varieties such as EPUB and pkpass use a different content type)
  # @param disposition[String] the content-disposition that will be passed to `send_stream` in Rails
  # @yield [Streamer] the streamer that can be written to
  # @return [ZipTricks::OutputEnumerator] The output enumerator assigned to the response body
  def zip_tricks_stream(filename: 'download.zip', type: 'application/zip', disposition: 'attachment', **zip_streamer_options, &zip_streaming_blk)
    # Make sure nginx buffering is suppressed - see https://github.com/WeTransfer/zip_tricks/issues/48
    response.headers['X-Accel-Buffering'] = 'no'
    enumerator = ZipTricks::Streamer.output_enum(**zip_streamer_options, &zip_streaming_blk)
    send_stream(filename: filename, type: type, disposition: disposition) do |stream|
      enumerator.each { |bytes| stream.write(bytes) }
    end
  end
end
