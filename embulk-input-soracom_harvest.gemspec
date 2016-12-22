
Gem::Specification.new do |spec|
  spec.name          = "embulk-input-soracom_harvest"
  spec.version       = "0.1.0"
  spec.authors       = ["Satoshi Akama"]
  spec.summary       = "SORACOM Harvest input plugin for Embulk"
  spec.description   = "Loads records from SORACOM Harvest."
  spec.email         = ["satoshiakama@gmail.com"]
  spec.licenses      = ["MIT"]
  spec.homepage      = "https://github.com/sakama/embulk-input-soracom_harvest"

  spec.files         = `git ls-files`.split("\n") + Dir["classpath/*.jar"]
  spec.test_files    = spec.files.grep(%r{^(test|spec)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'perfect_retry', '~> 0.5'
  spec.add_dependency 'httpclient', '>= 2.8.3'

  spec.add_development_dependency 'embulk', ['>= 0.8.15']
  spec.add_development_dependency 'bundler', ['>= 1.10.6']
  spec.add_development_dependency 'rake', ['>= 10.0']
  spec.add_development_dependency 'test-unit'
  spec.add_development_dependency 'test-unit-rr'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'codeclimate-test-reporter'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'gem_release_helper', '~> 1.0'
end
