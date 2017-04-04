require "bundler/gem_tasks"
require "rspec/core/rake_task"
require 'yard'

YARD::Rake::YardocTask.new(:doc) do |t|
  t.files = ['lib/**/*.rb', 'README.md', 'LICENSE.txt', 'IMPLEMENTATION_DETAILS.md']
end

RSpec::Core::RakeTask.new(:spec)
task :default => :spec
