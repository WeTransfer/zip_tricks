require_relative '../spec_helper'

describe ZipTricks::SizeEstimator do
  it 'accurately predicts the output zip size' do
    # Generate a couple of random files
    raw_file_1 = SecureRandom.random_bytes(1024 * 20)
    raw_file_2 = SecureRandom.random_bytes(1024 * 128)
    raw_file_3 = SecureRandom.random_bytes(1258695)

    predicted_size = described_class.estimate do | estimator |
      r = estimator.add_stored_entry(filename: "first-file.bin", size: raw_file_1.size)
      expect(r).to eq(estimator), "add_stored_entry should return self"

      estimator.add_stored_entry(filename: "second-file.bin", size: raw_file_2.size)

      r = estimator.add_compressed_entry(filename: "second-flie.bin", compressed_size: raw_file_3.size,
        uncompressed_size: raw_file_2.size, )
      expect(r).to eq(estimator), "add_compressed_entry should return self"
      
      r = estimator.add_stored_entry(filename: "first-file-with-descriptor.bin", size: raw_file_1.size,
        use_data_descriptor: true)
      expect(r).to eq(estimator), "add_stored_entry should return self"

      r = estimator.add_compressed_entry(filename: "second-file-with-descriptor.bin", compressed_size: raw_file_3.size,
        uncompressed_size: raw_file_2.size, use_data_descriptor: true)
      expect(r).to eq(estimator), "add_compressed_entry should return self"
    end

    expect(predicted_size).to eq(2690185)
  end
end
