module ZipInspection
  def inspect_zip_with_external_tool(path_to_zip)
    zipinfo_path = 'zipinfo'
    $zip_inspection_buf ||= StringIO.new
    $zip_inspection_buf.puts "\n"
    # The only way to get at the RSpec example without using the block argument
    $zip_inspection_buf.puts "Inspecting ZIP output of #{inspect}."
    $zip_inspection_buf.puts 'Be aware that the zipinfo version on OSX is too \
                              old to deal with Zip64.'
    escaped_cmd = Shellwords.join([zipinfo_path, '-tlhvz', path_to_zip])
    $zip_inspection_buf.puts `#{escaped_cmd}`
  end

  def open_with_external_app(app_path, path_to_zip, skip_if_missing)
    bin_exists = File.exist?(app_path)
    skip "This system does not have #{File.basename(app_path)}" if skip_if_missing && !bin_exists
    return unless bin_exists
    `#{Shellwords.join([app_path, path_to_zip])}`
  end

  def open_zip_with_archive_utility(path_to_zip, skip_if_missing: false)
    # ArchiveUtility sometimes puts the stuff it unarchives in ~/Downloads etc. so do
    # not perform any checks on the files since we do not really know where they are on disk.
    # Visual inspection should show whether the unarchiving is handled correctly.
    au_path = '/System/Library/CoreServices/Applications/Archive Utility.app/ \
              Contents/MacOS/Archive Utility'
    open_with_external_app(au_path, path_to_zip, skip_if_missing)
  end
end
