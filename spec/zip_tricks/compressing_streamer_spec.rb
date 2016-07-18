require_relative '../spec_helper'

describe ZipTricks::CompressingStreamer do
  
  it 'creates an archive that can be opened by Rubyzip, with a small number of very tiny text files' do
    tf = ManagedTempfile.new('zip')
    z = described_class.open(tf) do |zip|
      zip.write_stored_file('defl.bin') do |sink|
        sink << File.read(__dir__ + '/war-and-peace.txt')
      end
      zip.write_stored_file('stor.bin') do |sink|
        sink << File.read(__dir__ + '/war-and-peace.txt')
      end
    end
    tf.flush
    
    Zip::File.open(tf.path) do |zip_file|
      entries = zip_file.to_a
      expect(entries.length).to eq(2)
      entries.each_with_index do |entry, i|
        $stderr.puts("Decoding #{i}")
        # Make sure it is tagged as UNIX
        expect(entry.fstype).to eq(3)

         # The CRC
        expect(entry.crc).to eq(Zlib.crc32(File.read(__dir__ + '/war-and-peace.txt')))

        # Check the name
        expect(entry.name).to match(/\.bin$/)

        # Check the right external attributes (non-executable on UNIX)
        expect(entry.external_file_attributes).to eq(2175008768)
        
        # Check the file contents
        readback = entry.get_input_stream.read
        readback.force_encoding(Encoding::BINARY)
        expect(readback[0..10]).to eq(File.read(__dir__ + '/war-and-peace.txt')[0..10])
      end
    end

    inspect_zip_with_external_tool(tf.path)
  end
end
