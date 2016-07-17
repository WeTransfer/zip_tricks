require 'rubygems'
require 'bundler'
Bundler.setup
require_relative '../lib/zip_tricks'

war_and_peace = File.open(__dir__ + '/in/war-and-peace.txt', 'rb'){|f| f.read }.freeze
war_and_peace_crc = Zlib.crc32(war_and_peace)

image_file     = File.open(__dir__ + '/in/VTYL8830.jpg', 'rb'){|f| f.read }.freeze
image_file_crc = Zlib.crc32(image_file)

$tests_performed = 0
$builder_threads = []
at_exit { $builder_threads.map(&:join) }

def build_test(test_description)
  $tests_performed += 1
  
  test_file_base = test_description.downcase.gsub(/\-/, '').gsub(/[\s\:]+/, '_')
  filename = '%02d-%s.zip' % [$tests_performed, test_file_base]
  
  puts 'Test %02d: %s' % [$tests_performed, test_description]
  puts filename
  puts ""
  
  $builder_threads << Thread.new do
    File.open(File.join(__dir__, filename + '.tmp'), 'wb') do |of|
      ZipTricks::Streamer.open(of) do |zip|
        yield(zip)
      end
    end
    File.rename(File.join(__dir__, filename + '.tmp'), File.join(__dir__, filename))
  end
end

build_test "Two small stored files" do |zip|
  zip.add_stored_entry('text.txt', war_and_peace.bytesize, war_and_peace_crc)
  zip << war_and_peace
  
  zip.add_stored_entry('image.jpg', image_file.bytesize, image_file_crc)
  zip << image_file
end

build_test "Filename with diacritics" do |zip|
  zip.add_stored_entry('Kungälv.txt', war_and_peace.bytesize, war_and_peace_crc)
  zip << war_and_peace
end

build_test "Purely UTF-8 filename" do |zip|
  zip.add_stored_entry('Война и мир.txt', war_and_peace.bytesize, war_and_peace_crc)
  zip << war_and_peace
end

# The trick of this test is that each file of the 2, on it's own, does _not_ exceed the
# size threshold for Zip64. Together, however, they do.
build_test "Two entries larger than the overall Zip64 offset" do |zip|
  desired_minimum_size = (0xFFFFFFFF / 2) + 1024
  repeats = (desired_minimum_size.to_f / war_and_peace.bytesize).ceil
  crc_stream = ZipTricks::StreamCRC32.new
  repeats.times { crc_stream << war_and_peace }
  entry_size = war_and_peace.bytesize * repeats
  raise "Ooops" if entry_size < desired_minimum_size
  
  zip.add_stored_entry('repeated-A.txt', entry_size, crc_stream.to_i)
  repeats.times { zip << war_and_peace }
  
  zip.add_stored_entry('repeated-B.txt', entry_size, crc_stream.to_i)
  repeats.times { zip << war_and_peace }
end

build_test "One entry that requires Zip64 and a tiny entry following it" do |zip|
  desired_minimum_size = (0xFFFFFFFF) + 2048
  repeats = (desired_minimum_size.to_f / war_and_peace.bytesize).ceil
  crc_stream = ZipTricks::StreamCRC32.new
  repeats.times { crc_stream << war_and_peace }
  entry_size = war_and_peace.bytesize * repeats
  raise "Ooops" if entry_size < desired_minimum_size
  
  zip.add_stored_entry('large-requires-zip64.txt', entry_size, crc_stream.to_i)
  repeats.times { zip << war_and_peace }
  
  zip.add_stored_entry('repeated-B.txt', war_and_peace.bytesize, war_and_peace_crc)
  zip << war_and_peace
end

build_test "One tiny entry followed by second that requires Zip64" do |zip|
  zip.add_stored_entry('repeated-B.txt', war_and_peace.bytesize, war_and_peace_crc)
  zip << war_and_peace
  
  desired_minimum_size = (0xFFFFFFFF) + 6
  repeats = (desired_minimum_size.to_f / war_and_peace.bytesize).ceil
  crc_stream = ZipTricks::StreamCRC32.new
  repeats.times { crc_stream << war_and_peace }
  entry_size = war_and_peace.bytesize * repeats
  raise "Ooops" if entry_size < desired_minimum_size
  
  zip.add_stored_entry('large-requires-zip64.txt', entry_size, crc_stream.to_i)
  repeats.times { zip << war_and_peace }
end

build_test "Two entries both requiring Zip64" do |zip|
  desired_minimum_size = (0xFFFFFFFF) + 6
  repeats = (desired_minimum_size.to_f / war_and_peace.bytesize).ceil
  crc_stream = ZipTricks::StreamCRC32.new
  repeats.times { crc_stream << war_and_peace }
  entry_size = war_and_peace.bytesize * repeats
  raise "Ooops" if entry_size < desired_minimum_size
  
  zip.add_stored_entry('huge-1.bin', entry_size, crc_stream.to_i)
  repeats.times { zip << war_and_peace }

  zip.add_stored_entry('huge-2.bin', entry_size, crc_stream.to_i)
  repeats.times { zip << war_and_peace }
end
