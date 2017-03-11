require_relative '../spec_helper'

describe ZipTricks::RackBody do
  it 'is usable as a Rack response body, supports each() and close()' do
    output_buf = Tempfile.new('output')

    file_body = Random.new.bytes(1024 * 1024 + 8981)

    body = described_class.new do | zip |
      zip.add_stored_entry(filename: "A file", size: file_body.bytesize, crc32: Zlib.crc32(file_body))
      zip << file_body
    end

    body.each do | some_data |
      output_buf << some_data
    end
    body.close

    output_buf.rewind
    expect(output_buf.size).to eq(1057714)

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
