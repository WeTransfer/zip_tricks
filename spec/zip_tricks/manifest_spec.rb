require_relative '../spec_helper'

describe ZipTricks::Manifest do
  it 'builds a map of the contained ranges, and has its cumulative size match the predicted archive size exactly' do
    # Generate a couple of random files
    raw_file_1 = SecureRandom.random_bytes(1024 * 20)
    raw_file_2 = SecureRandom.random_bytes(1024 * 128)
    raw_file_3 = SecureRandom.random_bytes(1258695)
    
    manifest, bytesize = described_class.build do | builder |
      r = builder.add_stored_entry(name: "first-file.bin", size_uncompressed: raw_file_1.size)
      expect(r).to eq(builder), "add_stored_entry should return self"
      
      builder.add_stored_entry(name: "second-file.bin", size_uncompressed: raw_file_2.size)
      
      r = builder.add_compressed_entry(name: "second-file-comp.bin", size_uncompressed: raw_file_2.size, 
        size_compressed: raw_file_3.size, segment_info: 'http://example.com/second-file-deflated-segment.bin')
      expect(r).to eq(builder), "add_compressed_entry should return self"
    end
    
    require 'range_utils'
    
    expect(manifest).to be_kind_of(Array)
    total_size_of_all_parts = manifest.inject(0) do | total_bytes, span |
      total_bytes + RangeUtils.size_from_range(span.byte_range_in_zip)
    end
    expect(total_size_of_all_parts).to eq(1410595)
    expect(bytesize).to eq(1410595)
    
    expect(manifest.length).to eq(7)
    
    first_header = manifest[0]
    expect(first_header.part_type).to eq(:entry_header)
    expect(first_header.byte_range_in_zip).to eq(0..43)
    expect(first_header.filename).to eq("first-file.bin")
    expect(first_header.additional_metadata).to be_nil
    
    first_body = manifest[1]
    expect(first_body.part_type).to eq(:entry_body)
    expect(first_body.byte_range_in_zip).to eq(44..20523)
    expect(first_body.filename).to eq("first-file.bin")
    expect(first_body.additional_metadata).to be_nil
    
    third_header = manifest[4]
    expect(third_header.part_type).to eq(:entry_header)
    expect(third_header.byte_range_in_zip).to eq(151641..151690)
    expect(third_header.filename).to eq("second-file-comp.bin")
    expect(third_header.additional_metadata).to eq("http://example.com/second-file-deflated-segment.bin")
    
    third_body = manifest[5]
    expect(third_body.part_type).to eq(:entry_body)
    expect(third_body.byte_range_in_zip).to eq(151691..1410385)
    expect(third_body.filename).to eq("second-file-comp.bin")
    expect(third_body.additional_metadata).to eq("http://example.com/second-file-deflated-segment.bin")
    
    cd = manifest[-1]
    expect(cd.part_type).to eq(:central_directory)
    expect(cd.byte_range_in_zip).to eq(1410386..1410594)
  end
end
