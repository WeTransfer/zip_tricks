require_relative '../spec_helper'

describe ZipTricks::BlockDeflate do
  describe '.deflate_chunk' do
    it 'compresses a blob that can be inflated later'
    it 'removes the header'
    it 'removes the adler32'
    it 'removes the end marker'
  end
  
  describe '.deflate_in_blocks' do
    it 'honors the block size'
    it 'produces a blob that can be inflated later'
    it 'writes the end marker without the adler32'
  end
end
