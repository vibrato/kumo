#$:.push File.expand_path("../lib", __FILE__)
# Maintain your gem's version:
#require "kumo/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "kumo"
  s.version     = "0.0.1"
  s.authors     = ["James Martelletti"]
  s.email       = ["james@vibrato.com.au"]
  s.homepage    = "https://vibrato.com.au"
  s.summary     = "Commands"
  s.description = "Commands"

  s.files = Dir["{app,config,db,lib}/**/*", "Rakefile", "Readme.md"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "aws-sdk", "~> 2.2"
  s.add_dependency "sshkit"
  s.add_dependency "sshkey"
  s.add_dependency "thor"

  s.add_development_dependency "rspec"
end
