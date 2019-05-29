class ManagedTempfile < Tempfile
  @@managed_tempfiles = []

  def initialize(*)
    super
    @@managed_tempfiles << self
  end

  def self.prune!
    @@managed_tempfiles.each do |tf|
      begin
        tf.close
        tf.unlink
      rescue
        nil
      end
    end
    @@managed_tempfiles.clear
  end
end
