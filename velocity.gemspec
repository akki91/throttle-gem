# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'throttle/velocity/version'

Gem::Specification.new do |spec|
  spec.name          = "velocity"
  spec.version       = Throttle::Velocity::VERSION
  spec.authors       = ["Akshay khare"]
  spec.email         = ["akshay.khare@91gmail.com"]
  spec.summary       = %q{Rate Limiter}
  spec.description   = %q{Rate Limiter, based on throttling limits}
  spec.homepage      = "https://github.com/akki91/throttle"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
end
