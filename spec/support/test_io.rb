# frozen_string_literal: true

class TestIO
  attr_reader :size
  attr_accessor :pos

  def initialize(data, size)
    @win = data.dup
    @len = data.bytesize
    @size = size
    @pos = 0
  end

  def read(len = nil, buf = nil)
    if @pos >= @size || @pos < 0
      return (''.dup if len.to_i.zero?)
    end
    len = if len.nil?
      @size - @pos
    elsif @pos + len >= @size
      @size - @pos
    else
      (0 + len).to_i
    end
    cap = @win.bytesize
    off = @pos % @len
    need = off + len
    if need > cap
      q, r = need.divmod(cap)
      @win *= q if q > 1
      n = (@len + r - 1) / @len * @len
      # $stderr.puts "need: #{need} multiple: #{q} rem: #{r} copy: #{n}"
      @win << @win.byteslice(0, n) if n > 0
      # $stderr.puts "Grow TestIO window from #{cap} to #{@win.bytesize} (len: #{len} off: #{off})"
    end
    # puts [off, len].inspect
    if buf.nil?
      buf = @win.byteslice(off, len)
    else
      buf.replace(@win.byteslice(off, len))
    end
    @pos += buf.bytesize
    buf
  end

  def seek(pos, whence = nil)
    pos = (0 + pos).to_i
    case whence
    when nil, IO::SEEK_SET, :SET
      @pos = pos
    when IO::SEEK_CUR, :CUR
      @pos += pos
    when IO::SEEK_END, :END
      @pos = @size + pos
    else
      fail Errno::EINVAL, 'invalid whence'
    end
  end

  def rewind
    @pos = 0
  end

  def tell
    @pos
  end

  def eof?
    @pos >= @size
  end
end
