require_relative '../spec_helper'

describe ZipTricks::Microzip do
  it 'raises an exception if the filename is non-unique in the already existing set' do
    z = described_class.new(StringIO.new)
    z.add_local_file_header(filename: 'foo.txt', crc32: 0, compressed_size: 0, uncompressed_size: 0, storage_mode: 0)
    expect {
      z.add_local_file_header(filename: 'foo.txt', crc32: 0, compressed_size: 0, uncompressed_size: 0, storage_mode: 0)
    }.to raise_error(/already/)
  end

  it 'raises an exception if the filename does not fit in 0xFFFF bytes' do
    longest_filename_in_the_universe = "x" * (0xFFFF + 1)
    z = described_class.new(StringIO.new)
    expect {
      z.add_local_file_header(filename: longest_filename_in_the_universe, crc32: 0, compressed_size: 0, uncompressed_size: 0, storage_mode: 0)
    }.to raise_error(/filename/)
  end
end
