require 'bundler'
Bundler.setup

require 'benchmark'
require 'benchmark/ips'
require_relative '../lib/zip_tricks'

buffer_sizes = (0..128).map { |n| n * 1024 }

require 'benchmark/ips'
require 'tempfile'

rng = Random.new
# For a more accurate simulation let's assume that the
# files are being written into the ZIP piecewise, in chunks of
# 16KB.
blobs = (1..64).map { rng.bytes(16 * 1024) }
n_files = 256

Benchmark.ips do |x|
  x.config(time: 5, warmup: 0)
  buffer_sizes.each do |buf_size|
    x.report "Writes using a #{buf_size} byte buffer" do
      tf = Tempfile.new
      ZipTricks::Streamer.open(tf, write_buffer_size: buf_size) do |zip|
        n_files.times do |n|
          zip.write_stored_file("file-#{n}") do |sink|
            blobs.each do |blob_str|
              sink << blob_str
            end
          end
        end
      end
    ensure
      tf.close
    end
  end
  x.compare!
end

__END__

Calculating -------------------------------------
Writes using a 0 byte buffer
                          2.458  (± 0.0%) i/s -     12.000  in   5.289171s
Writes using a 512 byte buffer
                          2.584  (± 0.0%) i/s -     13.000  in   5.046729s
Writes using a 1024 byte buffer
                          2.466  (± 0.0%) i/s -     13.000  in   5.307981s
Writes using a 16384 byte buffer
                          2.373  (±42.1%) i/s -     10.000  in   5.026637s
Writes using a 32768 byte buffer
                          2.572  (± 0.0%) i/s -     13.000  in   5.088180s
Writes using a 65536 byte buffer
                          2.594  (± 0.0%) i/s -     13.000  in   5.031270s

Comparison:
Writes using a 65536 byte buffer:        2.6 i/s
Writes using a 512 byte buffer:        2.6 i/s - 1.00x  slower
Writes using a 32768 byte buffer:        2.6 i/s - 1.01x  slower
Writes using a 1024 byte buffer:        2.5 i/s - 1.05x  slower
Writes using a 0 byte buffer:        2.5 i/s - 1.06x  slower
Writes using a 16384 byte buffer:        2.4 i/s - same-ish: difference falls within error
