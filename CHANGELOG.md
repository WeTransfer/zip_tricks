## 5.1.0

* Slightly rework `RemoteIO` and `RemoteUncap` and make sure they work correctly by spinning up a test webserver
  to verify their operation. The changes to the documented API are fairly small so this is still marked as a minor
  release.

## 5.0.0

* Disable automatic filename deduplication by default, because it does not play nice with file/directory
  clobbering. The option can still be enabled by passing `auto_rename_duplicate_filenames: true` to the Streamer
  and all modules that use it
* Adopt [Hippocratic license v. 1.2](https://firstdonoharm.dev/version/1/2/license.html)
  Note that this might make the license conditions unacceptable for your project. If that is the case,
  you can use the 4.x branch of the library which stays under the original, exact MIT license.

## 4.8.0

* Make sure that when directories clobber files and vice versa we raise a clear error. Add `PathSet` which keeps track of entries
  and all the directories needed to create them, document `PathSet`
* Move the `uniquify_filenames` function into a module for easier removal later
* Add the `auto_rename_duplicate_filenames` parameter to `Streamer` constructor. We need to make this optional
  because making filenames unique can be very tricky when subdirectories are involved, and strictly
  speaking we should not be applying this transformation at all - there should be no output of
  duplicate filenames by the caller. So making the filenames should be available, but optional.

## 4.7.4

* Use a single fixed capacity string in StreamCRC32.from_io to avoid unnecessary allocations
* Fix a few tests that were calling out to external binaries

## 4.7.3

* Fix RemoteUncap#request_object_size to function correctly

## 4.7.2

* Relax bundler dependency so that both 1.x and 2.x are supported cleanly

## 4.7.1

* Bump rubyzip to 1.2.2 to mitigate CVE-2018-1000544

## 4.7.0

* Replace `RackBody` with `OutputEnumerator` since we want to provide a generic way of deferring ZIP output, also when using enumerators.
* Remove `RackBody#close` since we got nothing to close 🤷‍♂️
* Hint nginx that response buffering should be disabled when using Rails zip streaming

## 4.6.0

* Add `mtime:` option to all Streamer methods for adding files and directories, to permit setting modification time per-entry
* Optimize EOCD signature lookup when reading archives
* Reformat using the [we_transfer_style](https://rubygems.org/gems/we_transfer_style) Rubocop rules and conventions
* Add code of conduct and contribution guidelines
* Reduce the size of the CRC32 buffer to 64KB (backed by a benchmark), extract buffering into a wrapper proxy

## 4.5.2

* Replace the incorrectly used `file` type for empty directory entries with the appropriate `directory` type

## 4.5.1

* Speed up CRC32 calculation using a buffer of 5MB (have to combine CRCs less often)

## 4.5.0

* Rename `Streamer#add_compressed_entry` and `SizeEstimator#add_compressed_entry` to `add_deflated_entry`
  to indicate the type of compression that is going to get used.
* Make  `Streamer#write_(deflated|stored)_file` return a writable object that can be `.close`d, to
  permit usage of those methods in situations where suspending a block is inconvenient (make deferred writing possible).
* Fix CRC32 checksums in `Streamer#write_deflated_file`
* Add `Streamer#update_last_entry_and_write_data_descriptor` to permit externally-driven flows that use data descriptors

## 4.4.2

* Add 2.4 to Travis rubies
* Fix a severe performance degradation in Streamer with large file counts (https://github.com/WeTransfer/zip_tricks/pull/14)

## 4.4.1

* Tweak documentation a little

## 4.4.0

* Add `Streamer#add_empty_directory_entry` for writing empty directories/folders into the ZIP

## 4.3.0

* Add a native Rails streaming module for easier integration of ZipTricks into Rails controllers

## 4.2.4

* Get rid of Jeweler in favor of the standard Bundler/rubygems gem tasks

## 4.2.3

* Instead of BlockWrite, use intrim flushes of the same zlib Deflater

## 4.2.2

* Rewrite small data writes to perform less calls to `pack`

## 4.2.1

* Uniquify filenames during writes, so that the caller doesn't have to.

## 4.2.0

* Make it possible to swap the destination for Streamer writes, to improve `Range` support in the
  download server. Sometimes it might be useful to actually "redirect" the output to a different IO
  or buffer, without having to provide our own implementation of this switching.

## 4.1.0

* Implement brute-force straight-ahead reading of local file headers, for damaged or
  incomplete ZIP files

## 4.0.0

* Make reading local headers optional, since we need it but we don't have to use it for all archives. Ideally
  we should only do it when a reasonable central directory cannot be found. This can also happen under normal
  usage, when we are dealing with a ZIP-within-a-ZIP or when the end of the ZIP file has been truncated on
  write.
* Make sure `Writable#write` returns the number of bytes written (fix `IO.copy_stream` compatibility)

## 3.1.1

* Fix reading Zip64 extra fields. Only read fields that have corresponding "normal" fields set to overflow value.

## 3.1.0

* Fix `FileReader` failing where the EOCD marker would be detected multiple times at the end of a ZIP, which
  is something that _can_ happen during normal usage - a byte pattern has to appear twice to trigger the bug.
* Add support for archive comment customization

## 2.8.1

* Fix the bug with older versions of The Unarchiver refusing to open our Zip64 files

## 2.8.0

* Replace RubyZip with a clean-room ZIP writer, due to the overly elaborate Java-esque structure of RubyZip being hostile
  to modifications. The straw that broke the camel's back in this case is the insistence of RubyZip on writing out padding
  for the Zip64 extra fields in the local entries that it would never replace with useful data, which was breaking unarchiving
  when using Windows Explorer.

## 2.7.0

* Add `Streamer#write` so that the Streamer can be used as argument to `IO.copy_stream`

## 2.6.1

* Fi 0-byte reads in RemoteIO of RemoteUncap

## 2.6.0

* Set up open-source facilities (Github, Travis CI...)
* Add RemoteUncap for listing ZIP archives located on HTTP servers without having to download them.
  RemoteUncap downloads the central directory only using HTTP `Range` headers.

## 2.5.0

* Add Manifest for building a map of the ZIP file (for later Range support)

## 2.4.3  (Internal rel)

* Extract [very_tiny_state_machine](https://rubygems.org/gems/very_tiny_state_machine) gem from ZipTricks

## 2.4.1  (Internal rel)

* Include StreamCRC32 in the README

## 2.3.1  (Internal rel)

* Restore a streaming CRC facility

## 2.2.1  (Internal rel)

* Ensure WriteAndTell plays nice with strings in other encodings than BINARY

## 2.2.0  (Internal rel)

* Fix bytes_written return from deflate_in_blocks
* Raise on invalid Streamer IO arguments
* Set the EFS flag for UTF-8 filenames
* Add a RackBody object for plugging ZipTricks into Rack
* Add an offset wrapper for IOs given to Streamer, to support size estimation
* Ensure the given compression level is supported

## 2.0.0 (Internal rel)

* Implements streaming zip based on RubyZip
