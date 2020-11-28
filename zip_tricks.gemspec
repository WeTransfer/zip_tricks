lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'zip_tricks/version'

Gem::Specification.new do |spec|
  spec.name           = 'zip_tricks'
  spec.version        = ZipTricks::VERSION
  spec.authors        = ['Julik Tarkhanov', 'Noah Berman', 'Dmitry Tymchuk', 'David Bosveld', 'Felix Bünemann']
  spec.email          = ['me@julik.nl']

  spec.licenses       = ['MIT (Hippocratic)']
  spec.summary        = 'Stream out ZIP files from Ruby'
  spec.description    = 'Stream out ZIP files from Ruby'
  spec.homepage       = 'https://github.com/wetransfer/zip_tricks'

  # Prevent pushing this gem to RubyGems.org.
  # To allow pushes either set the 'allowed_push_host'
  # To allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
      'public gem pushes.'
  end

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir         = 'exe'
  spec.executables    = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths  = ['lib']

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rubyzip', '~> 1'

  spec.add_development_dependency 'rack', '~> 1.6' # For tests, where we spin up a server
  spec.add_development_dependency 'rake', '~> 12.2'
  spec.add_development_dependency 'rspec', '~> 3'
  spec.add_development_dependency 'complexity_assert'
  spec.add_development_dependency 'coderay'
  spec.add_development_dependency 'benchmark-ips'
  spec.add_development_dependency 'allocation_stats', '~> 0.1.5'
  spec.add_development_dependency 'yard', '~> 0.9'
  spec.add_development_dependency 'wetransfer_style', '0.6.0'
  spec.add_development_dependency 'puma'
end
