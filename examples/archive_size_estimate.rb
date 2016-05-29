require_relative '../lib/zip_tricks'

# Predict how large a ZIP file is going to be without having access to the actual
# file contents, but using just the filenames (influences the file size) and the size
# of the files
zip_archive_size_in_bytes = ZipTricks::StoredSizeEstimator.perform_fake_archiving do |zip|
  # Pretend we are going to make a ZIP file which contains a few
  # MP4 files (those do not compress all too well)
  zip.add_stored_entry("MOV_1234.MP4", 898090)
  zip.add_stored_entry("MOV_1235.MP4", 7855126)
end

zip_archive_size_in_bytes #=> 8753438