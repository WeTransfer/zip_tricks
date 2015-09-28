# zip_tricks

Makes Rubyzip dance for streaming. Spiritual successor to [zipline](https://github.com/fringd/zipline)

### OutputStreamPrefab

Is used to write a streaming ZIP file without compression when you know the CRC32 for the raw files
and the sizes of these files upfront. This writes the local headers immediately, without having to
rewind the output IO.

    # io has to be an object that supports :<< and :tell.
    io = ... # can be a Tempfile, but can also be a BlockWrite adapter for, say, Rack
    
    ZipTricks::OutputStreamPrefab.open(io) do | zip |
      zip.put_next_entry("first-file.bin", raw_file.size, raw_file_crc32)
      while blob = raw_file.read(2048)
        zip << blob
      end
      zip.put_next_entry("another-file.bin", another_file.size, another_file_crc32)
    end

## BlockWrite

Can be used as the destination IO, but will call the given block instead on every call to `:<<`.
This can be used to attach the output of the zip compressor to the Rack response body.

    # ...in your web app
    class ZipBody
      def each(&blk)
        io = ZipTricks::BlockWrite.new(&blk)
        ZipTricks::OutputStreamPrefab.open(io) do | zip |
          zip.put_next_entry("first-file.bin", raw_file.size, raw_file_crc32)
          while blob = raw_file.read(2048)
            zip << blob
          end
          ...
        end
      end
    end
    
    [200, {'Content-Type' => 'binary/octet-stream'}, ZipBody.new(...)]

## StoredSizeEstimator

Is used to predict the size of the ZIP after output, if the files are going to be stored without compression.
Takes the size of filenames and headers etc. into account.

    expected_zip_size = StoredSizeEstimator.perform_fake_archiving do | estimator |
      estimator.add_entry("file.doc", size=898291)
      estimator.add_entry("family.JPG", size=89281911)
    end
    # now you know how long the response will be
    content_length = expected_zip_size

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

