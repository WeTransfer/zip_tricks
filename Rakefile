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

class Jeweler
  module Specification
    def set_jeweler_defaults(base_dir, git_base_dir = nil)
      base_dir = File.expand_path(base_dir)
      git_base_dir = if git_base_dir
                       File.expand_path(git_base_dir)
                     else
                       base_dir
                     end
      can_git = git_base_dir && base_dir.include?(git_base_dir) && File.directory?(File.join(git_base_dir, '.git'))

      Dir.chdir(git_base_dir) do
        repo = if can_git
                 require 'git'
                 Git.open(git_base_dir)
               end

        if blank?(files) && repo
          base_dir_with_trailing_separator = File.join(base_dir, '')

          ignored_files = repo.lib.ignored_files + ['.gitignore']
          self.files = (repo.ls_files(base_dir).keys - ignored_files).compact.map do |file|
            File.expand_path(file).sub(base_dir_with_trailing_separator, '')
          end
        end

        if blank?(executables) && repo
          self.executables = (repo.ls_files(File.join(base_dir, 'bin')).keys - repo.lib.ignored_files).map do |file|
            File.basename(file)
          end
        end

        if blank?(extensions)
          self.extensions = FileList['ext/**/{extconf,mkrf_conf}.rb']
        end

        if blank?(extra_rdoc_files)
          self.extra_rdoc_files = FileList['README*', 'ChangeLog*', 'LICENSE*', 'TODO']
        end

        if File.exist?('Gemfile')
          require 'bundler'
          bundler = Bundler.load
          bundler.require(:default, :runtime).each do |dependency|
            add_dependency dependency.name, *dependency.requirement.as_list
          end
          bundler.require(:development).each do |dependency|
            add_development_dependency dependency.name, *dependency.requirement.as_list
          end
        end
      end
    end
  end
end

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
