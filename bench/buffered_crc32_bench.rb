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
                          0.054  (± 0.0%) i/s -      1.000  in  18.383019s
Single-byte <<-writes of 5242880 using a 256 byte buffer
                          0.121  (± 0.0%) i/s -      1.000  in   8.286061s
Single-byte <<-writes of 5242880 using a 512 byte buffer
                          0.124  (± 0.0%) i/s -      1.000  in   8.038112s
Single-byte <<-writes of 5242880 using a 1024 byte buffer
                          0.128  (± 0.0%) i/s -      1.000  in   7.828562s
Single-byte <<-writes of 5242880 using a 8192 byte buffer
                          0.123  (± 0.0%) i/s -      1.000  in   8.121586s
Single-byte <<-writes of 5242880 using a 16384 byte buffer
                          0.127  (± 0.0%) i/s -      1.000  in   7.872240s
Single-byte <<-writes of 5242880 using a 32768 byte buffer
                          0.126  (± 0.0%) i/s -      1.000  in   7.911816s
Single-byte <<-writes of 5242880 using a 65536 byte buffer
                          0.126  (± 0.0%) i/s -      1.000  in   7.917318s
Single-byte <<-writes of 5242880 using a 131072 byte buffer
                          0.127  (± 0.0%) i/s -      1.000  in   7.897223s
Single-byte <<-writes of 5242880 using a 262144 byte buffer
                          0.130  (± 0.0%) i/s -      1.000  in   7.675608s
Single-byte <<-writes of 5242880 using a 524288 byte buffer
                          0.130  (± 0.0%) i/s -      1.000  in   7.679886s
Single-byte <<-writes of 5242880 using a 1048576 byte buffer
                          0.128  (± 0.0%) i/s -      1.000  in   7.788439s
Single-byte <<-writes of 5242880 using a 2097152 byte buffer
                          0.128  (± 0.0%) i/s -      1.000  in   7.797839s

Comparison:
Single-byte <<-writes of 5242880 using a 262144 byte buffer:        0.1 i/s
Single-byte <<-writes of 5242880 using a 524288 byte buffer:        0.1 i/s - 1.00x  slower
Single-byte <<-writes of 5242880 using a 1048576 byte buffer:        0.1 i/s - 1.01x  slower
Single-byte <<-writes of 5242880 using a 2097152 byte buffer:        0.1 i/s - 1.02x  slower
Single-byte <<-writes of 5242880 using a 1024 byte buffer:        0.1 i/s - 1.02x  slower
Single-byte <<-writes of 5242880 using a 16384 byte buffer:        0.1 i/s - 1.03x  slower
Single-byte <<-writes of 5242880 using a 131072 byte buffer:        0.1 i/s - 1.03x  slower
Single-byte <<-writes of 5242880 using a 32768 byte buffer:        0.1 i/s - 1.03x  slower
Single-byte <<-writes of 5242880 using a 65536 byte buffer:        0.1 i/s - 1.03x  slower
Single-byte <<-writes of 5242880 using a 512 byte buffer:        0.1 i/s - 1.05x  slower
Single-byte <<-writes of 5242880 using a 8192 byte buffer:        0.1 i/s - 1.06x  slower
Single-byte <<-writes of 5242880 using a 256 byte buffer:        0.1 i/s - 1.08x  slower
Single-byte <<-writes of 5242880 using a 1 byte buffer:        0.1 i/s - 2.39x  slower
