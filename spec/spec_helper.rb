$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
$LOAD_PATH.unshift(File.dirname(__FILE__))

# $oldrss =`ps -o rss= -p #$$`.to_i

require 'rspec'
require 'zip_tricks'
require 'digest'
require 'fileutils'
require 'shellwords'
require 'zip'

require_relative 'support/read_monitor'
require_relative 'support/managed_tempfile'
require_relative 'support/zip_inspection'
require_relative 'support/allocate_under_matcher'
require_relative 'support/test_io'
require_relative 'support/null_io'

RSpec.configure do |config|
  config.include ZipInspection

  config.before :suite do
    # $rss =`ps -o rss= -p #$$`.to_i
    # $stderr.puts "RSS: #{$rss>>10}M +#{($rss-$oldrss)>>10}M"
  end

  config.after :each do
    ManagedTempfile.prune!
    # $rss, oldrss = `ps -o rss= -p #$$`.to_i, $rss
    # $stderr.puts "RSS: #{$rss>>10}M +#{($rss-oldrss)>>10}M"
  end

  config.after :suite do
    $stderr << $zip_inspection_buf.string if $zip_inspection_buf
    # $rss = `ps -o rss= -p #$$`.to_i
    # $stderr.puts "RSS: #{$rss>>10}M +#{($rss-$oldrss)>>10}M"
  end
end
