# frozen_string_literal: true

require_relative '../lib/zip_tricks'

# An example of how you can create a Rack endpoint for your ZIP downloads.
# NEVER run this in production - it is a huge security risk.
# What this app will do is pick PATH_INFO (your request URL path)
# and grab a file located at this path on your filesystem. The file will then
# be added to a ZIP archive created completely programmatically. No data will
# be cached on disk and the contents of the ZIP file will _not_ be buffered in
# it's entirety before sending. Unless you use a buffering Rack server of
# course (WEBrick or Thin).
class ZipDownload
  def call(env)
    file_path = env['PATH_INFO'] # Should be the absolute path on the filesystem

    # Open the file for binary reading
    f = File.open(file_path, 'rb')
    filename = File.basename(file_path)

    # Compute the CRC32 upfront. We do not use local footers for post-computing
    # the CRC32, so you _do_ have to precompute it beforehand. Ideally, you
    # would do that before storing the files you will be sending out later on.
    crc32 = ZipTricks::StreamCRC32.from_io(f)
    f.rewind

    # Compute the size of the download, so that a
    # real Content-Length header can be sent. Also, if your download
    # stops at some point, the downloading browser will be able to tell
    # the user that the download stalled or was aborted in-flight.
    # Note that using the size estimator here does _not_ read or compress
    # your original file, so it is very fast.
    size = ZipTricks::SizeEstimator.estimate do |ar|
      ar.add_stored_entry(filename, f.size)
    end

    # Create a suitable Rack response body, that will support each(),
    # close() and all the other methods. We can then return it up the stack.
    zip_response_body = ZipTricks::RackBody.new do |zip|
      begin
        # We are adding only one file to the ZIP here, but you could do that
        # with an arbitrary number of files of course.
        zip.add_stored_entry(filename: filename, size: f.size, crc32: crc32)
        # Write the contents of the file. It is stored, so the writes go
        # directly to the Rack output, bypassing any RubyZip
        # deflaters/compressors. In fact you are yielding the "blob" string
        # here directly to the Rack server handler.
        IO.copy_stream(f, zip)
      ensure
        f.close # Make sure the opened file we read from gets closed
      end
    end

    # Add a Content-Disposition so that the download has a .zip extension
    # (this will not work well with UTF-8 filenames on Windows, but hey!)
    content_disposition = format('attachment; filename=%s.zip', filename)

    # and return the response, adding the Content-Length we have computed earlier
    [
      200,
      {'Content-Length' => size.to_s, 'Content-Disposition' => content_disposition},
      zip_response_body
    ]
  end
end
