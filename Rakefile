require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'yard'
require 'rubocop/rake_task'

YARD::Rake::YardocTask.new(:doc) do |t|
  # The dash has to be between the two to "divide" the source files and
  # miscellaneous documentation files that contain no code
  t.files = ['lib/**/*.rb', '-', 'LICENSE.txt', 'IMPLEMENTATION_DETAILS.md']
end

RSpec::Core::RakeTask.new(:spec)
task default: :spec

RuboCop::RakeTask.new
