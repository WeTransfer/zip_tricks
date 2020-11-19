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
    @io << bytes.b
    @pos += bytes.bytesize
    self
  end

  def advance_position_by(num_bytes)
    @pos += num_bytes
  end

  def tell
    @pos
  end
end
