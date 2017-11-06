require 'bundler'
Bundler.setup

require 'benchmark'
require 'benchmark/ips'
require_relative '../lib/zip_tricks'

n_bytes = 5 * 1024 * 1024
r = Random.new
bytes = (0...n_bytes).map { r.bytes(1) }
buffer_sizes = [
  1,
  256,
  512,
  1024,
  8 * 1024,
  16 * 1024,
  32 * 1024,
  64 * 1024,
  128 * 1024,
  256 * 1024,
  512 * 1024,
  1024 * 1024,
  2 * 1024 * 1024
]

require 'benchmark/ips'


Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  buffer_sizes.each do |buf_size|
    x.report "Single-byte <<-writes of #{n_bytes} using a #{buf_size} byte buffer" do
      crc = ZipTricks::WriteBuffer.new(ZipTricks::StreamCRC32.new, buf_size)
      bytes.each { |b| crc << b }
      crc.to_i
    end
  end
  x.compare!
end

__END__

Warming up --------------------------------------
Single-byte <<-writes of 5242880 using a 1 byte buffer
                         1.000  i/100ms
Single-byte <<-writes of 5242880 using a 256 byte buffer
                         1.000  i/100ms
Single-byte <<-writes of 5242880 using a 512 byte buffer
                         1.000  i/100ms
Single-byte <<-writes of 5242880 using a 1024 byte buffer
                         1.000  i/100ms
Single-byte <<-writes of 5242880 using a 8192 byte buffer
                         1.000  i/100ms
Single-byte <<-writes of 5242880 using a 16384 byte buffer
                         1.000  i/100ms
Single-byte <<-writes of 5242880 using a 32768 byte buffer
                         1.000  i/100ms
Single-byte <<-writes of 5242880 using a 65536 byte buffer
                         1.000  i/100ms
Single-byte <<-writes of 5242880 using a 131072 byte buffer
                         1.000  i/100ms
Single-byte <<-writes of 5242880 using a 262144 byte buffer
                         1.000  i/100ms
Single-byte <<-writes of 5242880 using a 524288 byte buffer
                         1.000  i/100ms
Single-byte <<-writes of 5242880 using a 1048576 byte buffer
                         1.000  i/100ms
Single-byte <<-writes of 5242880 using a 2097152 byte buffer
                         1.000  i/100ms
Calculating -------------------------------------
Single-byte <<-writes of 5242880 using a 1 byte buffer
                          0.056  (± 0.0%) i/s -      1.000  in  17.757238s
Single-byte <<-writes of 5242880 using a 256 byte buffer
                          0.125  (± 0.0%) i/s -      1.000  in   7.990842s
Single-byte <<-writes of 5242880 using a 512 byte buffer
                          0.129  (± 0.0%) i/s -      1.000  in   7.723896s
Single-byte <<-writes of 5242880 using a 1024 byte buffer
                          0.131  (± 0.0%) i/s -      1.000  in   7.634909s
Single-byte <<-writes of 5242880 using a 8192 byte buffer
                          0.134  (± 0.0%) i/s -      1.000  in   7.458469s
Single-byte <<-writes of 5242880 using a 16384 byte buffer
                          0.134  (± 0.0%) i/s -      1.000  in   7.455839s
Single-byte <<-writes of 5242880 using a 32768 byte buffer
                          0.134  (± 0.0%) i/s -      1.000  in   7.484182s
Single-byte <<-writes of 5242880 using a 65536 byte buffer
                          0.136  (± 0.0%) i/s -      1.000  in   7.340512s
Single-byte <<-writes of 5242880 using a 131072 byte buffer
                          0.137  (± 0.0%) i/s -      1.000  in   7.314390s
Single-byte <<-writes of 5242880 using a 262144 byte buffer
                          0.133  (± 0.0%) i/s -      1.000  in   7.496164s
Single-byte <<-writes of 5242880 using a 524288 byte buffer
                          0.135  (± 0.0%) i/s -      1.000  in   7.417235s
Single-byte <<-writes of 5242880 using a 1048576 byte buffer
                          0.136  (± 0.0%) i/s -      1.000  in   7.355934s
Single-byte <<-writes of 5242880 using a 2097152 byte buffer
                          0.135  (± 0.0%) i/s -      1.000  in   7.389307s

Comparison:
<<<<<<< HEAD
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
=======
Single-byte <<-writes of 5242880 using a 131072 byte buffer:        0.1 i/s
Single-byte <<-writes of 5242880 using a 65536 byte buffer:        0.1 i/s - 1.00x  slower
Single-byte <<-writes of 5242880 using a 1048576 byte buffer:        0.1 i/s - 1.01x  slower
Single-byte <<-writes of 5242880 using a 2097152 byte buffer:        0.1 i/s - 1.01x  slower
Single-byte <<-writes of 5242880 using a 524288 byte buffer:        0.1 i/s - 1.01x  slower
Single-byte <<-writes of 5242880 using a 16384 byte buffer:        0.1 i/s - 1.02x  slower
Single-byte <<-writes of 5242880 using a 8192 byte buffer:        0.1 i/s - 1.02x  slower
Single-byte <<-writes of 5242880 using a 32768 byte buffer:        0.1 i/s - 1.02x  slower
Single-byte <<-writes of 5242880 using a 262144 byte buffer:        0.1 i/s - 1.02x  slower
Single-byte <<-writes of 5242880 using a 1024 byte buffer:        0.1 i/s - 1.04x  slower
Single-byte <<-writes of 5242880 using a 512 byte buffer:        0.1 i/s - 1.06x  slower
Single-byte <<-writes of 5242880 using a 256 byte buffer:        0.1 i/s - 1.09x  slower
Single-byte <<-writes of 5242880 using a 1 byte buffer:        0.1 i/s - 2.43x  slower
>>>>>>> When we say "byte" it should be a byte
