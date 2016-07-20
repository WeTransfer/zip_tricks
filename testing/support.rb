require 'rubygems'
require 'bundler'
Bundler.setup
require_relative '../lib/zip_tricks'

$war_and_peace = File.open(__dir__ + '/in/war-and-peace.txt', 'rb'){|f| f.read }.freeze
$war_and_peace_crc = Zlib.crc32($war_and_peace)

$image_file     = File.open(__dir__ + '/in/VTYL8830.jpg', 'rb'){|f| f.read }.freeze
$image_file_crc = Zlib.crc32($image_file)

class BigEntry < Struct.new(:crc32, :size, :iterations)
  def write_to(io)
    iterations.times { io << $war_and_peace }
  end
end

def generate_big_entry(desired_minimum_size)
  repeats = (desired_minimum_size.to_f / $war_and_peace.bytesize).ceil
  crc_stream = ZipTricks::StreamCRC32.new
  repeats.times { crc_stream << $war_and_peace }
  entry_size = $war_and_peace.bytesize * repeats
  raise "Ooops" if entry_size < desired_minimum_size
  BigEntry.new(crc_stream.to_i, entry_size, repeats)
end

class TestDesc < Struct.new(:desc, :filename, :outcome)
end

$tests_performed = 0
$test_descs = []
$builder_threads = []
at_exit { $builder_threads.map(&:join) }
def build_test(test_description, desired_outcome: "Opens and files extract", streamer_class: ZipTricks::Streamer)
  $tests_performed += 1

  test_file_base = test_description.downcase.gsub(/\-/, '').gsub(/[\s\:]+/, '_')
  filename = '%02d-%s.zip' % [$tests_performed, test_file_base]

  puts 'Test %02d: %s' % [$tests_performed, test_description]
  puts filename
  puts ""

  $test_descs << TestDesc.new(test_description, filename, desired_outcome)
  $builder_threads << Thread.new do
    File.open(File.join(__dir__, filename + '.tmp'), 'wb') do |of|
      streamer_class.open(of) do |zip|
        yield(zip)
      end
    end
    File.rename(File.join(__dir__, filename + '.tmp'), File.join(__dir__, filename))
  end
end
def xbuild_test(*); end # For quickly disabling them by prepending "x" (like RSpec)

$matrix = {}
def test_matrix_item(os_name, app_name)
  $matrix[os_name] ||= []
  $matrix[os_name] << app_name
end

def print_testing_matrix
end

at_exit { print_testing_matrix }
