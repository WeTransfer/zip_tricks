require_relative '../spec_helper'

describe ZipTricks::SizeEstimator do
  it 'accurately predicts the output zip size' do
    # Generate a couple of random files
    raw_file_one = Random.new.bytes(1_024 * 20)
    raw_file_two = Random.new.bytes(1_024 * 128)
    raw_file_three = Random.new.bytes(1_258_695)

    predicted_size = described_class.estimate(auto_rename_duplicate_filenames: true) do |estimator|
      r = estimator.add_stored_entry(filename: 'first-file.bin', size: raw_file_one.size)
      expect(r).to eq(estimator), 'add_stored_entry should return self'

      estimator.add_stored_entry(filename: 'second-file.bin', size: raw_file_two.size)

      # This filename will be deduplicated and will therefore grow in size
      r = estimator.add_deflated_entry(filename: 'second-file.bin',
                                       compressed_size: raw_file_three.size,
                                       uncompressed_size: raw_file_two.size)
      expect(r).to eq(estimator), 'add_deflated_entry should return self'

      r = estimator.add_stored_entry(filename: 'first-file-with-descriptor.bin',
                                     size: raw_file_one.size,
                                     use_data_descriptor: true)
      expect(r).to eq(estimator), 'add_stored_entry should return self'

      r = estimator.add_deflated_entry(filename: 'second-file-with-descriptor.bin',
                                       compressed_size: raw_file_three.size,
                                       uncompressed_size: raw_file_two.size,
                                       use_data_descriptor: true)
      expect(r).to eq(estimator), 'add_deflated_entry should return self'

      r = estimator.add_empty_directory_entry(dirname: 'empty-directory/')
      expect(r).to eq(estimator), 'add_deflated_entry should return self'
    end

    expect(predicted_size).to eq(2_690_321)
  end

  it 'passes the keyword arguments to Streamer#new' do
    expect {
      described_class.estimate(auto_rename_duplicate_filenames: false) do |estimator|
        estimator.add_stored_entry(filename: 'first-file.bin', size: 123)
        estimator.add_stored_entry(filename: 'first-file.bin', size: 123)
      end
    }.to raise_error(ZipTricks::PathSet::Conflict)

    size = described_class.estimate(auto_rename_duplicate_filenames: true) do |estimator|
      estimator.add_stored_entry(filename: 'first-file.bin', size: 123)
      estimator.add_stored_entry(filename: 'first-file.bin', size: 123)
    end
    expect(size).to eq(549)
  end

  it 'still supports #add_compressed_entry (to be removed in v.5)' do
    predicted_size = described_class.estimate do |zip|
      zip.add_compressed_entry(filename: 'foo.bar', compressed_size: 123, uncompressed_size: 456)
    end
    expect(predicted_size).to be > 0
  end
end
