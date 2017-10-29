# frozen_string_literal: true

require_relative '../lib/zip_tricks'

# Predict how large a ZIP file is going to be without having access to
# the actual file contents, but using just the filenames (influences the
# file size) and the size of the files
zip_archive_size_in_bytes = ZipTricks::SizeEstimator.estimate do |zip|
  # Pretend we are going to make a ZIP file which contains a few
  # MP4 files (those do not compress all too well)
  zip.add_stored_entry(filename: 'MOV_1234.MP4', size: 898_090)
  zip.add_stored_entry(filename: 'MOV_1235.MP4', size: 7_855_126)
end

puts zip_archive_size_in_bytes #=> 8_753_467
