# frozen_string_literal: true

require_relative '../lib/zip_tricks'
require 'tempfile'

# This shows how to perform compression in parallel (a-la pigz, but in a less
# advanced fashion since the compression tables are not shared - to
# minimize shared state).
#
# When using this approach, compressing a large file can be performed as a
# map-reduce operation.
# First you prepare all the data per part of your (potentially very large) file,
# and then you use the reduce task to combine that data into one linear zip.
# In this example we will generate threads and collect their return values in
# the order the threads were launched, which guarantees a consistent reduce.
#
# So, let each thread generate a part of the file, and also
# compute the CRC32 of it. The thread will compress it's own part
# as well, in an independent deflate segment - the threads do not share
# anything. You could also multiplex this over multiple processes or
# even machines.
threads = (0..12).map do
  Thread.new do
    source_tempfile = Tempfile.new 't'
    source_tempfile.binmode

    # Fill the part with random content
    12.times { source_tempfile << Random.new.bytes(1 * 1024 * 1024) }
    source_tempfile.rewind

    # Compute the CRC32 of the source file
    part_crc = ZipTricks::StreamCRC32.from_io(source_tempfile)
    source_tempfile.rewind

    # Create a compressed part
    compressed_tempfile = Tempfile.new('tc')
    compressed_tempfile.binmode
    ZipTricks::BlockDeflate.deflate_in_blocks(source_tempfile,
                                              compressed_tempfile)

    source_tempfile.close!
    # The data that the splicing process needs.
    [compressed_tempfile, part_crc, source_tempfile.size]
  end
end

# Threads return us a tuple with [compressed_tempfile, source_part_size,
# source_part_crc]
compressed_tempfiles_and_crc_of_parts = threads.map(&:join).map(&:value)

# Now we need to compute the CRC32 of the _entire_ file, and it has to be
# the CRC32 of the _source_ file (uncompressed), not of the compressed variant.
# Handily we know
entire_file_crc = ZipTricks::StreamCRC32.new
compressed_tempfiles_and_crc_of_parts.each do |_, source_part_crc, source_part_size|
  entire_file_crc.append(source_part_crc, source_part_size)
end

# We need to append the the terminator bytes to the end of the last part.
last_compressed_part = compressed_tempfiles_and_crc_of_parts[-1][0]
ZipTricks::BlockDeflate.write_terminator(last_compressed_part)

# and we need to know how big the deflated segment of the ZIP is going to be, in total.
# To figure that out we just sum the sizes of the files
compressed_part_files = compressed_tempfiles_and_crc_of_parts.map(&:first)
size_of_deflated_segment = compressed_part_files.map(&:size).inject(&:+)
size_of_uncompressed_file = compressed_tempfiles_and_crc_of_parts.map { |e| e[2] }.inject(&:+)

# And now we can create a ZIP with our compressed file in it's entirety.
# We use a File as a destination here, but you can also use a socket or a
# non-rewindable IO. ZipTricks never needs to rewind your output, since it is
# made for streaming.
output = File.open('zip_created_in_parallel.zip', 'wb')

ZipTricks::Streamer.open(output) do |zip|
  zip.add_deflated_entry('parallel.bin',
                         size_of_uncompressed_file,
                         entire_file_crc.to_i,
                         size_of_deflated_segment)
  compressed_part_files.each do |part_file|
    part_file.rewind
    while blob = part_file.read(2048)
      zip << blob
    end
  end
end
