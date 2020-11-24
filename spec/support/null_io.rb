# frozen_string_literal: true

class NullIO
  def initialize
    @size = 0
  end

  def <<(str)
    @size += str.bytesize
    self
  end

  def read(len, _buf = nil)
    ''.dup if len.to_i == 0
  end

  def write(*args)
    @size += args.sum(&:bytesize)
  end

  def size
    @size
  end
end
