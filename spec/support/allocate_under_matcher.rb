require 'allocation_stats' if RUBY_ENGINE == 'ruby'

RSpec::Matchers.define :allocate_under do |expected|
  match do |actual|
    unless RUBY_ENGINE == 'ruby'
      skip "allocation tracing not supported on #{RUBY_ENGINE}"
    end
    @trace = actual.is_a?(Proc) ? AllocationStats.trace(&actual) : actual
    @trace.new_allocations.size < expected
  end

  def objects
    self
  end

  def supports_block_expectations?
    true
  end

  def output_trace_info(trace)
    trace.allocations(alias_paths: true).group_by(:sourcefile, :sourceline, :class).to_text
  end

  failure_message do |_actual|
    "expected under #{expected} objects to be allocated; got #{@trace.new_allocations.size}:\n\n" << output_trace_info(@trace)
  end

  description do
    "allocates under #{expected} objects"
  end
end
