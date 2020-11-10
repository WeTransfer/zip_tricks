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
end
