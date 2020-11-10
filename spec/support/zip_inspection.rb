require 'rbconfig'

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

  def open_with_external_app(cmd, skip_if_missing)
    app_path = cmd.first
    bin_exists = File.exist?(app_path)
    skip "This system does not have #{File.basename(app_path)}" if skip_if_missing && !bin_exists
    return unless bin_exists
    system(*cmd)
  end

  def open_zip_with_archive_utility(path_to_zip, skip_if_missing: false, expected_content: [])
    unless RbConfig::CONFIG['host_os'].start_with? 'darwin'
      skip "Archive Utility specs require macOS"
      return
    end
    # ArchiveUtility sometimes puts the stuff it unarchives in ~/Downloads etc. so
    # we reset the preferences to unpack to current dir and don't show in Finder.
    dearchive_reveal_after = `/usr/bin/defaults read com.apple.archiveutility dearchive-reveal-after`.to_i == 1
    dearchive_into = `/usr/bin/defaults read com.apple.archiveutility dearchive-into`.chomp
    # rubocop:disable Lint/UnneededSplatExpansion
    begin
      system *%w[/usr/bin/defaults write com.apple.archiveutility dearchive-reveal-after -bool false]
      system *%w[/usr/bin/defaults delete com.apple.archiveutility dearchive-into] unless dearchive_into.empty?
      cmd = %W[/usr/bin/open -WFjngb com.apple.archiveutility #{path_to_zip}]
      result = open_with_external_app(cmd, skip_if_missing)
    ensure
      system *%W[/usr/bin/defaults write com.apple.archiveutility dearchive-reveal-after -bool #{dearchive_reveal_after}]
      system *%W[/usr/bin/defaults write com.apple.archiveutility dearchive-into -string #{dearchive_into}] unless dearchive_into.empty?
    end
    # rubocop:enable Lint/UnneededSplatExpansion
    expect(result).to be(true)
    zip_path = File.join(File.dirname(path_to_zip), File.basename(path_to_zip, ".zip"))
    expect(Dir.exist?(zip_path)).to be(true)
    expect(Dir.entries(zip_path)[2..-1]).to match_array(expected_content)
  end
end
