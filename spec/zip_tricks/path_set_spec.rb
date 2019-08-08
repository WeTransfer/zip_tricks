require 'spec_helper'

describe ZipTricks::PathSet do
  it 'allows adding multiple files' do
    expect {
      subject.add_file_path('foo.txt')
      subject.add_file_path('bar.txt')
      subject.add_file_path('baz.txt')
      subject.add_directory_path('subdir')
    }.not_to raise_error
  end

  it 'does not raise when a directory gets added twice' do
    expect {
      subject.add_directory_path('subdir')
      subject.add_directory_path('subdir')
    }.not_to raise_error
  end

  it 'raises when a file would clobber a directory' do
    subject.add_directory_path('maybe-dir-maybe-file')
    expect {
      subject.add_file_path('maybe-dir-maybe-file')
    }.to raise_error(described_class::FileClobbersDirectory)
  end

  it 'raises when a directory would clobber a file' do
    subject.add_file_path('maybe-dir-maybe-file')
    expect {
      subject.add_directory_path('maybe-dir-maybe-file')
    }.to raise_error(described_class::DirectoryClobbersFile)
  end

  it 'raises when a file would clobber a directory to create its implicit subtree' do
    subject.add_file_path('a/b/c/d/e/f')
    expect {
      subject.add_file_path('a/b/c/d/e/f/g')
    }.to raise_error(described_class::DirectoryClobbersFile)
  end

  it 'raises when a directory would clobber a file to create its implicit subtree' do
    subject.add_file_path('a/b/c/d/e/f')
    expect {
      subject.add_directory_path('a/b/c/d/e/f/g')
    }.to raise_error(described_class::DirectoryClobbersFile)
  end

  describe '#include?' do
    it 'answers both for specifically added items and for their path components' do
      subject.add_file_path('dir1/dir2/file.doc')
      subject.add_directory_path('another-dir/')

      expect(subject).to include('dir1')
      expect(subject).to include('dir1/dir2')
      expect(subject).to include('dir1/dir2/file.doc')
      expect(subject).to include('another-dir')

      expect(subject).not_to include('dir2') # This is only included with its parent
      expect(subject).not_to include('not-there') # Just not in this set
    end
  end

  describe '#clear' do
    it 'deletes elements' do
      subject.add_file_path('f')
      subject.add_directory_path('d')

      expect(subject).to include('d')
      expect(subject).to include('f')

      subject.clear

      expect(subject).not_to include('d')
      expect(subject).not_to include('f')
    end
  end
end
