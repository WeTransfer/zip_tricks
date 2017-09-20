# coding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'zip_tricks/version'

Gem::Specification.new do |spec|
  spec.name           = 'zip_tricks'
  spec.version        = ZipTricks::VERSION
  spec.authors        = ['Julik Tarkhanov']
  spec.email          = ['me@julik.nl']

  spec.summary        = 'Stream out ZIP files from Ruby'
  spec.description    = 'Stream out ZIP files from Ruby'
  spec.homepage       = 'http://github.com/wetransfer/zip_tricks'

  # Prevent pushing this gem to RubyGems.org.
  # To allow pushes either set the 'allowed_push_host'
  # To allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
      'public gem pushes.'
  end

  # Be friendly to automated scavenging systems / dependency tracking servers
  s.metadata = {
    'source_code_uri' => 'https://github.com/WeTransfer/zip_tricks',
    'changelog_uri'   => 'https://github.com/WeTransfer/zip_tricks/blob/master/CHANGELOG.md',
    'documentation_uri' => 'http://www.rubydoc.info/gems/zip_tricks',
  }

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir         = 'exe'
  spec.executables    = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths  = ['lib']

  spec.add_development_dependency 'bundler', '~> 1'
  spec.add_development_dependency 'rubyzip', '~> 1.1'
  spec.add_development_dependency 'terminal-table'
  spec.add_development_dependency 'range_utils'

  spec.add_development_dependency 'rack', '~> 1.6' # For Jeweler
  spec.add_development_dependency 'rake', '~> 10.4'
  spec.add_development_dependency 'rspec', '~> 3'
  spec.add_development_dependency 'complexity_assert'
  spec.add_development_dependency 'coderay'
  spec.add_development_dependency 'yard', '~> 0.9'
  spec.add_development_dependency 'rubocop'
end
