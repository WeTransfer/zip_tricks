require_relative '../spec_helper'

describe ZipTricks::OutputEnumerator do
  it 'returns parts of the ZIP file when called via #each with immediate yield' do
    output_buf = Tempfile.new('output')

    file_body = Random.new.bytes(1024 * 1024 + 8981)

    body = described_class.new do |zip|
      zip.add_stored_entry(filename: 'A file',
                           size: file_body.bytesize,
                           crc32: Zlib.crc32(file_body))
      zip << file_body
    end

    body.each do |some_data|
      output_buf << some_data
    end

    output_buf.rewind
    expect(output_buf.size).to eq(1_057_714)

    per_filename = {}
    Zip::File.open(output_buf.path) do |zip_file|
      # Handle entries one by one
      zip_file.each do |entry|
        # The entry name gets returned with a binary encoding, we have to force it back.
        per_filename[entry.name] = entry.get_input_stream.read
      end
    end

    expect(per_filename).to have_key('A file')
    expect(per_filename['A file'].bytesize).to eq(file_body.bytesize)
  end

  it 'buffers writes to the set boundary' do
    file_body = Random.new.bytes(1024 * 7)
    bufsize = 11 * 1024
    body = described_class.new(write_buffer_size: bufsize, write_transform: :dup) do |zip|
      5.times do |n|
        zip.add_stored_entry(filename: "file-#{n}",
                             size: file_body.bytesize,
                             crc32: Zlib.crc32(file_body))
        zip << file_body
      end
    end

    output_segments = body.each.to_a

    expect(output_segments.length).to eq(4)
    expect(output_segments[0].bytesize).to eq(bufsize)
    expect(output_segments[1].bytesize).to eq(bufsize)
    expect(output_segments[2].bytesize).to eq(bufsize)
    # the last segment may be smaller
    expect(output_segments[3].bytesize).to be > 0
    expect(output_segments[3].bytesize).to be < bufsize
  end

  it 'returns parts of the ZIP file when called using an Enumerator' do
    output_buf = Tempfile.new('output')

    file_body = Random.new.bytes(1024 * 1024 + 8981)

    body = described_class.new do |zip|
      zip.add_stored_entry(filename: 'A file',
                           size: file_body.bytesize,
                           crc32: Zlib.crc32(file_body))
      zip << file_body
    end

    enum = body.each
    enum.each do |some_data|
      output_buf << some_data
    end

    output_buf.rewind
    expect(output_buf.size).to eq(1_057_714)

    per_filename = {}
    Zip::File.open(output_buf.path) do |zip_file|
      # Handle entries one by one
      zip_file.each do |entry|
        # The entry name gets returned with a binary encoding, we have to force it back.
        per_filename[entry.name] = entry.get_input_stream.read
      end
    end

    expect(per_filename).to have_key('A file')
    expect(per_filename['A file'].bytesize).to eq(file_body.bytesize)
  end
end
