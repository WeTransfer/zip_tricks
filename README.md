# zip_tricks

[![Build Status](https://travis-ci.org/WeTransfer/zip_tricks.svg?branch=master)](https://travis-ci.org/WeTransfer/zip_tricks)

Allows streaming, non-rewinding ZIP file output from Ruby.
Spiritual successor to [zipline](https://github.com/fringd/zipline)

Requires Ruby 2.1+, rubyzip and a couple of other gems (all available to jRuby as well).

## Upgrading from versions 1.x and 2.x to 3.x

The API of the library has changed, please review the documentation.

## Create a ZIP file without size estimation, compress on-the-fly)

When you compress on the fly and use data descriptors it is not really possible to compute the file size upfront.
But it is very likely to yield good compression - especially if you send things like CSV files.

    out = my_tempfile # can also be a socket
    ZipTricks::Streamer.open(out) do |zip|
      zip.write_stored_file('mov.mp4.txt') do |sink|
        File.open('mov.mp4', 'rb'){|source| IO.copy_stream(source, sink) }
      end
      zip.write_deflated_file('long-novel.txt') do |sink|
        File.open('novel.txt', 'rb'){|source| IO.copy_stream(source, sink) }
      end
    end

## Send the same ZIP file from a Rack response

Create a `RackBody` object and give it's constructor a block that adds files.
The block will only be called when actually sending the response to the client
(unless you are using a buffering Rack webserver, such as Webrick).

    body = ZipTricks::RackBody.new do | zip |
      zip.write_stored_file('mov.mp4.txt') do |sink|
        File.open('mov.mp4', 'rb'){|source| IO.copy_stream(source, sink) }
      end
      zip.write_deflated_file('long-novel.txt') do |sink|
        File.open('novel.txt', 'rb'){|source| IO.copy_stream(source, sink) }
      end
    end
    [200, {'Transfer-Encoding' => 'chunked'}, body]

## Send a ZIP file of known size, with correct headers

Use the `SizeEstimator` to compute the correct size of the resulting archive.

    zip_body = ZipTricks::RackBody.new do | zip |
      zip.add_stored_entry(filename: "myfile1.bin", size: 9090821, crc32: 12485)
      zip << read_file('myfile1.bin')
      zip.add_stored_entry(filename: "myfile2.bin", size: 458678, crc32: 89568)
      zip << read_file('myfile2.bin')
    end
    bytesize = ZipTricks::SizeEstimator.estimate do |z|
     z.add_stored_entry(filename: 'myfile1.bin', size: 9090821)
     z.add_stored_entry(filename: 'myfile2.bin', size: 458678)
    end
    [200, {'Content-Length' => bytesize.to_s}, zip_body]

## Other usage examples

Check out the `examples/` directory at the root of the project. This will give you a good idea
of various use cases the library supports.

## Writing ZIP files using the Streamer bypass

You do not have to "feed" all the contents of the files you put in the archive through the Streamer object.
If the write destination for your use case is a `Socket` (say, you are writing using Rack hijack) and you know
the metadata of the file upfront (the CRC32 of the uncompressed file and the sizes), you can write directly
to that socket using some accelerated writing technique, and only use the Streamer to write out the ZIP metadata.

    # io has to be an object that supports #<<
    ZipTricks::Streamer.open(io) do | zip |
      # raw_file is written "as is" (STORED mode).
      # Write the local file header first..
      zip.add_stored_entry("first-file.bin", raw_file.size, raw_file_crc32)
      
      # then send the actual file contents bypassing the Streamer interface
      io.sendfile(my_temp_file)
      
      # ...and then adjust the ZIP offsets within the Streamer
      zip.simulate_write(my_temp_file.size)
    end

## RackBody

Can be used to output a streamed ZIP archive directly through a Rack response body.
The block given to the constructor will be called when the response body will be read by the webserver,
and will receive a {ZipTricks::Streamer} as it's block argument. You can then add entries to the Streamer as usual.
The archive will be automatically closed at the end of the block.

    # Precompute the Content-Length ahead of time
    content_length = ZipTricks::SizeEstimator.estimate do | estimator |
      estimator.add_stored_entry('large.tif', size=1289894)
    end
    
    # Prepare the response body. The block will only be called when the response starts to be written.
    body = ZipTricks::RackBody.new do | streamer |
      streamer.add_stored_entry('large.tif', size=1289894, crc32=198210)
      streamer << large_file.read(1024*1024) until large_file.eof?
      ...
    end
    
    [200, {'Content-Type' => 'binary/octet-stream', 'Content-Length' => content_length.to_s}, body]
  
## BlockWrite

Can be used as the destination IO, but will call the given block instead on every call to `:<<`.
This can be used to attach the output of the zip compressor to the Rack response body, or another
destination. For Rack/Rails just use RackBody since it sets this up for you.

    io = ZipTricks::BlockWrite.new{|data| socket << data }
    ZipTricks::Streamer.open(io) do | zip |
      zip.add_stored_entry("first-file.bin", raw_file.size, raw_file_crc32)
      ....
    end

## SizeEstimator

Is used to predict the size of the ZIP archive after output. This can be used to generate, say, a `Content-Length` header,
or to predict the size of the resulting archive on the storage device. The size is estimated using a very fast "fake archiving"
procedure, so it computes the sizes of all the headers and the central directory very accurately.

    expected_zip_archive_size = SizeEstimator.estimate do | estimator |
      estimator.add_stored_entry("file.doc", size=898291)
      estimator.add_compressed_entry("family.JPG", size=89281911, compressed_size=89218)
    end


## StreamCRC32

Computes the CRC32 value in a streaming fashion. Is slightly more convenient for the purpose than using the raw Zlib
library functions.

    crc = ZipTricks::StreamCRC32.new
    crc << large_file.read(1024 * 12) until large_file.eof?
    ...
    
    crc.to_i # Returns the actual CRC32 value computed so far
    ...
    # Append a known CRC32 value that has been computed previosuly
    crc.append(precomputed_crc32, size_of_the_blob_computed_from)

## Contributing to zip_tricks
 
* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.
* Fork the project.
* Start a feature/bugfix branch.
* Commit and push until you are happy with your contribution.
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

## Copyright

Copyright (c) 2015 WeTransfer. See LICENSE.txt for
further details.
