# frozen_string_literal: true

# A tiny wrapper over any object that supports :<<.
# Adds :tell and :advance_position_by.
class ZipTricks::WriteAndTell
  def initialize(io)
    @io = io
    @pos = 0
  end

  def <<(bytes)
    return self if bytes.nil?
    binary_bytes = binary(bytes)
    @io << binary_bytes
    @pos += binary_bytes.bytesize
    self
  end

  def advance_position_by(num_bytes)
    @pos += num_bytes
  end

  def tell
    @pos
  end

  private

  def binary(str)
    return str if str.encoding == Encoding::BINARY
    str.force_encoding(Encoding::BINARY)
  rescue RuntimeError # the string is frozen
    str.dup.force_encoding(Encoding::BINARY)
  end
end
