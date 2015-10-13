# zip_tricks

Makes Rubyzip sing, dance and play saxophone for streaming applications.
Spiritual successor to [zipline](https://github.com/fringd/zipline)

The library is composed of a loose set of modules which are described below.

## BlockDeflate

Deflate a byte stream in blocks of N bytes, optionally writing a terminator marker. This can be used to
compress a file in parts.

    source_file = File.open('12_gigs.bin', 'rb')
    compressed = Tempfile.new
    # Will not compress everything in memory, but do it per chunk to spare memory. `compressed`
    # will be written to at the end of each chunk.
    ZipTricks::BlockDeflate.deflate_in_blocks_and_terminate(source_file, compressed)

You can also do the same to parts that you will later concatenate together elsewhere, in that case
you need to skip the end marker:

    compressed = Tempfile.new
    ZipTricks::BlockDeflate.deflate_in_blocks(File.open('part1.bin', 'rb), compressed)
    ZipTricks::BlockDeflate.deflate_in_blocks(File.open('part2.bin', 'rb), compressed)
    ZipTricks::BlockDeflate.deflate_in_blocks(File.open('partN.bin', 'rb), compressed)
    ZipTricks::BlockDeflate.write_terminator(compressed)

You can also elect to just compress strings in memory (to splice them later):

    compressed_string = ZipTricks::BlockDeflate.deflate_chunk(big_string)

## Streamer

Is used to write a streaming ZIP file when you know the CRC32 for the raw files
and the sizes of these files upfront. This writes the local headers immediately, without having to
rewind the output IO. It also avoids using the local footers instead of headers, therefore permitting
Zip64-sized entries to be stored easily.

    # io has to be an object that supports #<<, #tell and #close
    io = ... # can be a Tempfile, but can also be a BlockWrite adapter for, say, Rack
    
    ZipTricks::Streamer.open(io) do | zip |
      
      # raw_file is written "as is" (STORED mode)
      zip.add_stored_entry("first-file.bin", raw_file.size, raw_file_crc32)
      while blob = raw_file.read(2048)
        zip << blob
      end
      
      # another_file is assumed to be block-deflated (DEFLATE mode)
      zip.add_compressed_entry("another-file.bin", another_file_size, another_file_crc32, compressed_file.size)
      while blob = compressed_file.read(2048)
        zip << blob
      end
      
      # If you are storing block-deflated parts of a single file, you have to terminate the output
      # with an end marker manually
      zip.add_compressed_entry("compressed-in-parts.bin", another_file_size, another_file_crc32, deflated_size)
      while blob = part1.read(2048)
        zip << blob
      end
      while blob = part2.read(2048)
        zip << blob
      end
      zip << ZipTricks::BlockDeflate::END_MARKER
      
      ... # more file writes etc.
    end

## BlockWrite

Can be used as the destination IO, but will call the given block instead on every call to `:<<`.
This can be used to attach the output of the zip compressor to the Rack response body.

    # ...in your web app
    class ZipBody
      def each(&blk)
        io = ZipTricks::BlockWrite.new(&blk)
        ZipTricks::Streamer.open(io) do | zip |
          zip.add_stored_entry("first-file.bin", raw_file.size, raw_file_crc32)
          ....
        end
      end
    end
    
    [200, {'Content-Type' => 'binary/octet-stream'}, ZipBody.new(...)]

## StoredSizeEstimator

Is used to predict the size of the ZIP archive after output. This can be used to generate, say, a `Content-Length` header,
or to predict the size of the resulting archive on the storage device. The size is estimated using a very fast "fake archiving"
procedure, so it computes the sizes of all the headers and the central directory very accurately.

    expected_zip_archive_size = StoredSizeEstimator.perform_fake_archiving do | estimator |
      estimator.add_stored_entry("file.doc", size=898291)
      estimator.add_compressed_entry("family.JPG", size=89281911, compressed_size=89218)
    end


## Contributing to zip_tricks
 
* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.
* Fork the project.
* Start a feature/bugfix branch.
* Commit and push until you are happy with your contribution.
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

## Copyright

Copyright (c) 2015 Julik Tarkhanov. See LICENSE.txt for
further details.

