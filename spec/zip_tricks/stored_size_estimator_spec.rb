require_relative '../spec_helper'

describe ZipTricks::StoredSizeEstimator do
  it 'accurately predicts the output zip size' do
    # Generate a couple of random files
    raw_file_1 = SecureRandom.random_bytes(1024 * 20)
    raw_file_2 = SecureRandom.random_bytes(1024 * 128)
    raw_file_3 = SecureRandom.random_bytes(1258695)

    predicted_size = described_class.perform_fake_archiving do | estimator |
      r = estimator.add_stored_entry("first-file.bin", raw_file_1.size)
      expect(r).to eq(estimator), "add_stored_entry should return self"

      estimator.add_stored_entry("second-file.bin", raw_file_2.size)

      r = estimator.add_compressed_entry("second-file.bin", raw_file_2.size, raw_file_3.size)
      expect(r).to eq(estimator), "add_compressed_entry should return self"
    end

    expect(predicted_size).to eq(1410524)
  end
end
