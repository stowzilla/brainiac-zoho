# frozen_string_literal: true

require_relative "lib/brainiac/plugins/zoho/version"

Gem::Specification.new do |s|
  s.name        = "brainiac-zoho"
  s.version     = Brainiac::Plugins::Zoho::VERSION
  s.summary     = "Zoho Mail webhook plugin for Brainiac"
  s.description = "Zoho Mail integration for Brainiac — receives email webhooks, matches rules, " \
                  "sends notifications, and optionally triages support emails into work items. " \
                  "Includes OAuth flow for Zoho Mail API access."
  s.authors     = ["Andy Davis"]
  s.homepage    = "https://github.com/stowzilla/brainiac-zoho"
  s.license     = "MIT"
  s.required_ruby_version = ">= 3.4"

  s.files = Dir["lib/**/*.rb", "templates/**/*", "README.md", "LICENSE"]
  s.require_paths = ["lib"]

  s.add_dependency "brainiac", ">= 0.0.14"

  s.add_development_dependency "minitest", "~> 5.25"
  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "rubocop", "~> 1.75"
  s.add_development_dependency "rubocop-performance", "~> 1.25"

  s.metadata["rubygems_mfa_required"] = "true"
end
