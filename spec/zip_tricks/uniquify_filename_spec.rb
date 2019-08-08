require 'spec_helper'

describe ZipTricks::UniquifyFilename do
  it 'returns the filename as is if it is not present in the check set' do
    check_set = Set.new
    expect(described_class.call("file.txt", check_set)).to eq("file.txt")
    expect(check_set).to be_empty, "Should not have added anything to the check set"
  end

  it 'deduplicates the filename if it is already contained in the set of unique names' do
    check_set = Set.new(["foo.txt"])
    expect(described_class.call("foo.txt", check_set)).to eq("foo (1).txt")
  end

  it 'deduplicates the filename and increments the counter as long as necessary to arrive at a unique one' do
    check_set = Set.new(["foo.txt", "foo (1).txt", "foo (2).txt"])
    expect(described_class.call("foo.txt", check_set)).to eq("foo (3).txt")
  end

  it 'when the filename extension is .gd and there is an extension in front of it, inserts the counter before that extension' do
    check_set = Set.new(["foo.data.gz"])
    expect(described_class.call("foo.data.gz", check_set)).to eq("foo (1).data.gz")
  end
end
