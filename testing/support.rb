require 'rubygems'
require 'bundler'
Bundler.setup
require_relative '../lib/zip_tricks'
require 'terminal-table'

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

TestDesc = Struct.new(:title, :filename)

$tests_performed = 0
$test_descs = []
$builder_threads = []
at_exit { $builder_threads.map(&:join) }

def build_test(test_description, streamer_class: ZipTricks::Streamer)
  $tests_performed += 1

  test_file_base = test_description.downcase.gsub(/\-/, '').gsub(/[\s\:]+/, '_')
  filename = '%02d-%s.zip' % [$tests_performed, test_file_base]

  puts 'Test %02d: %s' % [$tests_performed, test_description]
  puts filename
  puts ""

  $test_descs << TestDesc.new(test_description, filename)
  $builder_threads << Thread.new do
    File.open(File.join(__dir__, filename + '.tmp'), 'wb') do |of|
      streamer_class.open(of) do |zip|
        yield(zip)
      end
    end
    File.rename(File.join(__dir__, filename + '.tmp'), File.join(__dir__, filename))
  end
end

# For quickly disabling them by prepending "x" (like RSpec)
def xbuild_test(*)
end

# Prints a text file that you can then fill in
def prepare_test_protocol
  File.open(__dir__ + '/test-report.txt', 'wb') do |f|
    platforms = [
      "OSX 10.11 - Archive Utility (builtin)",
      "OSX - The Unarchiver 3.10",
      "Windows7 x64 - Builtin Explorer ZIP opener",
      "Windows7 x64 - 7Zip 9.20",
    ]
    platforms.each do |platform_name|
      f.puts ''
      table = Terminal::Table.new title: platform_name, headings: ['Test', 'Outcome']
      $test_descs.each_with_index do |desc, i|
        test_name = [desc.filename, '%s' % desc.title].join("\n")
        outcome = ' ' * 64
        table << [test_name, outcome]
        table << :separator if i < ($test_descs.length - 1)
      end
      f.puts table
    end
  end
end

at_exit { prepare_test_protocol }
