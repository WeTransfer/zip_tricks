require_relative '../spec_helper'

describe ZipTricks::BlockDeflate do
  describe '.deflate_chunk' do
    it 'compresses a blob that can be inflated later'
    it 'removes the header'
    it 'removes the adler32'
    it 'removes the end marker'
    it 'honors the level'
  end
  
  describe 'deflate_in_blocks_and_terminate' do
    it 'honors the block size'
    it 'produces a blob that can be inflated later'
    it 'writes the end marker without the adler32'
  end
  
  describe '.write_terminator' do
    it 'writes the terminator and returns 2 for number of bytes written'
  end
  
  describe '.deflate_in_blocks' do
    it 'honors the block size'
    it 'honors the level and passes it to deflate_chunk'
    it 'produces a blob that can be inflated later'
    it 'does not write the end marker'
  end
end
