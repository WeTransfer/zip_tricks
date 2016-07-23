require_relative 'support'

test_matrix_item "OSX", "ArchiveUtility (built-in)"
test_matrix_item "OSX", "The Unarchiver (3.11.1)"
test_matrix_item "Windows 7", "Explorer"
test_matrix_item "Windows 7", "7Zip 9.20"

build_test "Two small stored files" do |zip|
  zip.add_stored_entry('text.txt', $war_and_peace.bytesize, $war_and_peace_crc)
  zip << $war_and_peace

  zip.add_stored_entry('image.jpg', $image_file.bytesize, $image_file_crc)
  zip << $image_file
end

build_test "Filename with diacritics" do |zip|
  zip.add_stored_entry('Kungälv.txt', $war_and_peace.bytesize, $war_and_peace_crc)
  zip << $war_and_peace
end

build_test "Purely UTF-8 filename" do |zip|
  zip.add_stored_entry('Война и мир.txt', $war_and_peace.bytesize, $war_and_peace_crc)
  zip << $war_and_peace
end

# The trick of this test is that each file of the 2, on it's own, does _not_ exceed the
# size threshold for Zip64. Together, however, they do.
build_test "Two entries larger than the overall Zip64 offset" do |zip|
  big = generate_big_entry((0xFFFFFFFF / 2) + 1024)
  zip.add_stored_entry('repeated-A.txt', big.size, big.crc32)
  big.write_to(zip)

  zip.add_stored_entry('repeated-B.txt', big.size, big.crc32)
  big.write_to(zip)
end

build_test "One entry that requires Zip64 and a tiny entry following it" do |zip|
  big = generate_big_entry(0xFFFFFFFF + 2048)
  zip.add_stored_entry('large-requires-zip64.bin', big.size, big.crc32)
  big.write_to(zip)

  zip.add_stored_entry('tiny-after.txt', $war_and_peace.bytesize, $war_and_peace_crc)
  zip << $war_and_peace
end

build_test "One tiny entry followed by second that requires Zip64" do |zip|
  zip.add_stored_entry('tiny-at-start.txt', $war_and_peace.bytesize, $war_and_peace_crc)
  zip << $war_and_peace

  big = generate_big_entry(0xFFFFFFFF + 2048)
  zip.add_stored_entry('large-requires-zip64.bin', big.size, big.crc32)
  big.write_to(zip)
end

build_test "Two entries both requiring Zip64" do |zip|
  big = generate_big_entry(0xFFFFFFFF + 2048)
  zip.add_stored_entry('huge-file-1.bin', big.size, big.crc32)
  big.write_to(zip)

  zip.add_stored_entry('huge-file-2.bin', big.size, big.crc32)
  big.write_to(zip)
end

DD = ZipTricks::CompressingStreamer 

build_test "Five different entries (stored/deflated) using data descriptors", streamer_class: DD do |zip|
  zip.write_stored_file('stored.1.bin') do |sink|
    sink << Random.new.bytes(1024 * 1024 * 4)
  end
  zip.write_stored_file('stored.2.bin') do |sink|
    sink << Random.new.bytes(1024 * 1024 * 2)
  end
  zip.write_deflated_file('compressed_text.txt') do |sink|
    sink << $war_and_peace
  end
  zip.write_stored_file('stored.3.bin') do |sink|
    sink << Random.new.bytes(1024 * 1024 * 1)
  end
  zip.write_deflated_file('deflated.4.bin') do |sink|
    sink << Random.new.bytes(1024 * 1024 * 2)
  end
end

build_test "Two entries larger than the overall Zip64 offset using data descriptors", streamer_class: DD do |zip|
  big = generate_big_entry((0xFFFFFFFF / 2) + 1024)
  
  zip.write_stored_file('repeated-A.txt') do |sink|
    big.write_to(sink)
  end
  
  zip.write_stored_file('repeated-B.txt') do |sink|
    big.write_to(sink)
  end
end
