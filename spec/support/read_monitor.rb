require 'delegate'

class ReadMonitor < SimpleDelegator
  def read(*)
    super.tap do
      @num_reads ||= 0
      @num_reads += 1
    end
  end

  def num_reads
    @num_reads || 0
  end
end
