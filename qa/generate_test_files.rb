# frozen_string_literal: true

require_relative 'support'

build_test 'Two small stored files' do |zip|
  zip.add_stored_entry(filename: 'text.txt',
                       size: $war_and_peace.bytesize,
                       crc32: $war_and_peace_crc)
  zip << $war_and_peace

  zip.add_stored_entry(filename: 'image.jpg',
                       size: $image_file.bytesize,
                       crc32: $image_file_crc)
  zip << $image_file
end

build_test 'Two small stored files and an empty directory' do |zip|
  zip.add_stored_entry(filename: 'text.txt',
                       size: $war_and_peace.bytesize,
                       crc32: $war_and_peace_crc)
  zip << $war_and_peace

  zip.add_stored_entry(filename: 'image.jpg',
                       size: $image_file.bytesize,
                       crc32: $image_file_crc)
  zip << $image_file

  zip.add_empty_directory(dirname: 'Chekov')
end

build_test 'Filename with diacritics' do |zip|
  zip.add_stored_entry(filename: 'Kungälv.txt',
                       size: $war_and_peace.bytesize,
                       crc32: $war_and_peace_crc)
  zip << $war_and_peace
end

build_test 'Purely UTF-8 filename' do |zip|
  zip.add_stored_entry(filename: 'Война и мир.txt',
                       size: $war_and_peace.bytesize,
                       crc32: $war_and_peace_crc)
  zip << $war_and_peace
end

# The trick of this test is that each file of the 2, on it's own, does _not_ exceed the
# size threshold for Zip64. Together, however, they do.
build_test 'Two entries larger than the overall Zip64 offset' do |zip|
  big = generate_big_entry((0xFFFFFFFF / 2) + 1_024)
  zip.add_stored_entry(filename: 'repeated-A.txt',
                       size: big.size,
                       crc32: big.crc32)
  big.write_to(zip)

  zip.add_stored_entry(filename: 'repeated-B.txt',
                       size: big.size,
                       crc32: big.crc32)
  big.write_to(zip)
end

build_test 'One entry that requires Zip64 and a tiny entry following it' do |zip|
  big = generate_big_entry(0xFFFFFFFF + 2_048)
  zip.add_stored_entry(filename: 'large-requires-zip64.bin',
                       size: big.size,
                       crc32: big.crc32)
  big.write_to(zip)

  zip.add_stored_entry(filename: 'tiny-after.txt',
                       size: $war_and_peace.bytesize,
                       crc32: $war_and_peace_crc)
  zip << $war_and_peace
end

build_test 'One tiny entry followed by second that requires Zip64' do |zip|
  zip.add_stored_entry(filename: 'tiny-at-start.txt',
                       size: $war_and_peace.bytesize,
                       crc32: $war_and_peace_crc)
  zip << $war_and_peace

  big = generate_big_entry(0xFFFFFFFF + 2_048)
  zip.add_stored_entry(filename: 'large-requires-zip64.bin',
                       size: big.size,
                       crc32: big.crc32)
  big.write_to(zip)
end

build_test 'Two entries both requiring Zip64' do |zip|
  big = generate_big_entry(0xFFFFFFFF + 2_048)
  zip.add_stored_entry(filename: 'huge-file-1.bin',
                       size: big.size,
                       crc32: big.crc32)
  big.write_to(zip)

  zip.add_stored_entry(filename: 'huge-file-2.bin',
                       size: big.size,
                       crc32: big.crc32)
  big.write_to(zip)
end

build_test 'Two stored entries using data descriptors' do |zip|
  zip.write_stored_file('stored.1.bin') do |sink|
    sink << Random.new.bytes(1_024 * 1_024 * 4)
  end
  zip.write_stored_file('stored.2.bin') do |sink|
    sink << Random.new.bytes(1_024 * 1_024 * 3)
  end
end

build_test 'One entry deflated using data descriptors' do |zip|
  big = generate_big_entry(0xFFFFFFFF / 64)
  zip.write_deflated_file('war-and-peace-repeated-compressed.txt') do |sink|
    big.write_to(sink)
  end
end

build_test 'Two entries larger than the overall Zip64 offset using data descriptors' do |zip|
  big = generate_big_entry((0xFFFFFFFF / 2) + 1_024)

  zip.write_stored_file('repeated-A.txt') { |sink| big.write_to(sink) }
  zip.write_stored_file('repeated-B.txt') { |sink| big.write_to(sink) }
end

build_test 'One stored entry larger than Zip64 threshold using data descriptors' do |zip|
  big = generate_big_entry(0xFFFFFFFF + 64_000)

  zip.write_stored_file('repeated-A.txt') { |sink| big.write_to(sink) }
end
