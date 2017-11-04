require 'bundler'
Bundler.setup

require 'benchmark'
require 'benchmark/ips'
require_relative '../lib/zip_tricks'

# Create an array of 15 bytes
data = Random.new.bytes(5*1024*1024).unpack("C*")
buffer_sizes = [
  1,
  256,
  512,
  1024,
  8*1024,
  16*1024,
  32*1024,
  64*1024,
  128*1024,
  256*1024,
  512*1024,
  1024*1024,
  2*1024*1024,
]

require 'benchmark/ips'

Benchmark.ips do |x|
  x.config(:time => 5, :warmup => 2)
  buffer_sizes.each do |buf_size|
    x.report "Single-byte <<-writes of #{data.length} using a #{buf_size} byte buffer" do
      crc = ZipTricks::WriteBuffer.new(ZipTricks::StreamCRC32.new, buf_size)
      data.each { |byte| crc << byte }
      crc.to_i
    end
  end
  x.compare!
end

__END__

julik@jet zip_tricks (buffer-write) $ ruby bench/buffered_crc32_bench.rb 
Warming up --------------------------------------
Single-bute writes of 5242880 using a 1 byte buffer
                         1.000  i/100ms
Single-bute writes of 5242880 using a 256 byte buffer
                         1.000  i/100ms
Single-bute writes of 5242880 using a 512 byte buffer
                         1.000  i/100ms
Single-bute writes of 5242880 using a 1024 byte buffer
                         1.000  i/100ms
Single-bute writes of 5242880 using a 8192 byte buffer
                         1.000  i/100ms
Single-bute writes of 5242880 using a 16384 byte buffer
                         1.000  i/100ms
Single-bute writes of 5242880 using a 32768 byte buffer
                         1.000  i/100ms
Single-bute writes of 5242880 using a 65536 byte buffer
                         1.000  i/100ms
Single-bute writes of 5242880 using a 131072 byte buffer
                         1.000  i/100ms
Single-bute writes of 5242880 using a 262144 byte buffer
                         1.000  i/100ms
Single-bute writes of 5242880 using a 524288 byte buffer
                         1.000  i/100ms
Single-bute writes of 5242880 using a 1048576 byte buffer
                         1.000  i/100ms
Single-bute writes of 5242880 using a 2097152 byte buffer
                         1.000  i/100ms
Calculating -------------------------------------
Single-bute writes of 5242880 using a 1 byte buffer
                          0.051  (± 0.0%) i/s -      1.000  in  19.438758s
Single-bute writes of 5242880 using a 256 byte buffer
                          0.287  (± 0.0%) i/s -      2.000  in   6.966893s
Single-bute writes of 5242880 using a 512 byte buffer
                          0.312  (± 0.0%) i/s -      2.000  in   6.400392s
Single-bute writes of 5242880 using a 1024 byte buffer
                          0.331  (± 0.0%) i/s -      2.000  in   6.036335s
Single-bute writes of 5242880 using a 8192 byte buffer
                          0.360  (± 0.0%) i/s -      2.000  in   5.558613s
Single-bute writes of 5242880 using a 16384 byte buffer
                          0.364  (± 0.0%) i/s -      2.000  in   5.489236s
Single-bute writes of 5242880 using a 32768 byte buffer
                          0.367  (± 0.0%) i/s -      2.000  in   5.451628s
Single-bute writes of 5242880 using a 65536 byte buffer
                          0.369  (± 0.0%) i/s -      2.000  in   5.426813s
Single-bute writes of 5242880 using a 131072 byte buffer
                          0.366  (± 0.0%) i/s -      2.000  in   5.459224s
Single-bute writes of 5242880 using a 262144 byte buffer
                          0.357  (± 0.0%) i/s -      2.000  in   5.594680s
Single-bute writes of 5242880 using a 524288 byte buffer
                          0.358  (± 0.0%) i/s -      2.000  in   5.590514s
Single-bute writes of 5242880 using a 1048576 byte buffer
                          0.357  (± 0.0%) i/s -      2.000  in   5.599562s
Single-bute writes of 5242880 using a 2097152 byte buffer
                          0.355  (± 0.0%) i/s -      2.000  in   5.626917s

Comparison:
Single-bute writes of 5242880 using a 65536 byte buffer:        0.4 i/s
Single-bute writes of 5242880 using a 32768 byte buffer:        0.4 i/s - 1.00x  slower
Single-bute writes of 5242880 using a 131072 byte buffer:        0.4 i/s - 1.01x  slower
Single-bute writes of 5242880 using a 16384 byte buffer:        0.4 i/s - 1.01x  slower
Single-bute writes of 5242880 using a 8192 byte buffer:        0.4 i/s - 1.02x  slower
Single-bute writes of 5242880 using a 524288 byte buffer:        0.4 i/s - 1.03x  slower
Single-bute writes of 5242880 using a 262144 byte buffer:        0.4 i/s - 1.03x  slower
Single-bute writes of 5242880 using a 1048576 byte buffer:        0.4 i/s - 1.03x  slower
Single-bute writes of 5242880 using a 2097152 byte buffer:        0.4 i/s - 1.04x  slower
Single-bute writes of 5242880 using a 1024 byte buffer:        0.3 i/s - 1.11x  slower
Single-bute writes of 5242880 using a 512 byte buffer:        0.3 i/s - 1.18x  slower
Single-bute writes of 5242880 using a 256 byte buffer:        0.3 i/s - 1.28x  slower
Single-bute writes of 5242880 using a 1 byte buffer:        0.1 i/s - 7.16x  slower