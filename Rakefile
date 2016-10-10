# encoding: utf-8

require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake'
require_relative 'lib/zip_tricks'
require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://guides.rubygems.org/specification-reference/ for more options
  gem.name = "zip_tricks"
  gem.homepage = "http://github.com/wetransfer/zip_tricks"
  gem.license = "MIT"
  gem.version = ZipTricks::VERSION
  gem.summary = 'Stream out ZIP files from Ruby'
  gem.description = 'Stream out ZIP files from Ruby'
  gem.email = "me@julik.nl"
  gem.authors = ["Julik Tarkhanov"]
  gem.files.exclude "testing/**/*"
  # dependencies defined in Gemfile
end
Jeweler::RubygemsDotOrgTasks.new

require 'rspec/core'
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
end

desc "Code coverage detail"
task :simplecov do
  ENV['COVERAGE'] = "true"
  Rake::Task['spec'].execute
end

task :default => :spec

require 'yard'
desc "Generate YARD documentation"
YARD::Rake::YardocTask.new do |t|
  t.files   = ['lib/**/*.rb', 'ext/**/*.c' ]
  t.options = ['--markup markdown']
  t.stats_options = ['--list-undoc']
end
