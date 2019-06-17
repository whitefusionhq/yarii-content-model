$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "mariposta-content-model/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "mariposta-content-model"
  s.version     = MaripostaContentModel::VERSION
  s.authors     = ["Jared White"]
  s.email       = ["jared@jaredwhite.com"]
  s.homepage    = "https://whitefusion.io"
  s.summary     = "Provides an ActiveRecord-like method of loading and saving static content files (from Jekyll, Hugo, etc.)"
  s.description = s.summary
  s.license     = "Copyright 2019 Whitefusion. All Rights Reserved"

  all_files       = `git ls-files -z`.split("\x0")
  s.files         = all_files.grep(%r{^(exe|lib)/|^.rubocop.yml$})

  s.add_dependency "rails", ">= 5.0", "< 7.0"
  s.add_dependency 'safe_yaml', '~> 1.0'
  s.add_dependency 'git', '~> 1.3'

  s.add_development_dependency "rspec-rails", "3.8.2"
end
