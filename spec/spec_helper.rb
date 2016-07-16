$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'rspec'
require 'zip_tricks'
require 'digest'

module Keepalive
  # Travis-CI kills the build if it does not receive output on standard out or standard error
  # for longer than a few minutes. We have a few tests that take a _very_ long time, and during
  # those tests this method has to be called every now and then to revive the output and let the
  # build proceed.
  def still_alive!
    $keepalive_last_out_ping_at ||= Time.now
    if (Time.now - $keepalive_last_out_ping_at) > 3
      $keepalive_last_out_ping_at = Time.now
      $stdout << '_'
    end
  end
  extend self
end


class ManagedTempfile < Tempfile
  @@managed_tempfiles = []
  
  def initialize(*)
    super
    @@managed_tempfiles << self
  end
  
  def self.prune!
    @@managed_tempfiles.each do |tf|
      (tf.close; tf.unlink) rescue nil
    end
    @@managed_tempfiles.clear
  end
end

# A Tempfile filled with N bytes of random data, that also knows the CRC32 of that data
class RandomFile < ManagedTempfile
  attr_reader :crc32
  RANDOM_MEG = Random.new.bytes(1024 * 1024) # Allocate it once to prevent heap churn
  def initialize(size)
    super('random-bin')
    binmode
    crc = ZipTricks::StreamCRC32.new
    bytes = size % (1024 * 1024)
    megs = size / (1024 * 1024)
    megs.times do
      Keepalive.still_alive!
      self << RANDOM_MEG
      crc << RANDOM_MEG
    end
    random_blob = Random.new.bytes(bytes)
    self << random_blob
    crc << random_blob
    @crc32 = crc.to_i
    rewind
  end

  def copy_to(io)
    rewind
    while data = read(10*1024*1024)
      io << data
      Keepalive.still_alive!
    end
    rewind
  end
end

module ZipInspection
  def inspect_zip_with_external_tool(path_to_zip)
    example_info = self.inspect # The only way to get at the RSpec example without using the block argument
    $zip_inspection_buf ||= StringIO.new
    $zip_inspection_buf.puts "\n"
    $zip_inspection_buf.puts "Inspecting ZIP output of #{example_info}."
    escaped_cmd = Shellwords.join(['zipinfo', '-tlhvz', path_to_zip])
    $zip_inspection_buf.puts `#{escaped_cmd}`
  end
end

RSpec.configure do |config|
  config.include Keepalive
  config.include ZipInspection
  
  config.after :each do
    ManagedTempfile.prune!
  end
  
  config.after :suite do
    $stderr << $zip_inspection_buf.string if $zip_inspection_buf
  end
end
