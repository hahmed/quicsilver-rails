# frozen_string_literal: true

require_relative "lib/quicsilver/rails/version"

Gem::Specification.new do |spec|
  spec.name = "quicsilver-rails"
  spec.version = Quicsilver::Rails::VERSION
  spec.authors = ["Haroon Ahmed"]
  spec.email = ["haroon.ahmed25@gmail.com"]

  spec.summary = "Rails integration experiments for Quicsilver HTTP/3 and WebTransport."
  spec.description = "Rails helpers, runners, and API experiments for using Quicsilver WebTransport from Rails applications."
  spec.homepage = "https://github.com/hahmed/quicsilver-rails"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # What the gem needs at runtime, plus its docs. Listed rather than excluded, so a new file in the
  # repository stays out of the gem until it is added here.
  spec.files = IO.popen(%w[git ls-files -z -- app config docs lib], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true)
  end + %w[README.md CHANGELOG.md LICENSE]
  spec.require_paths = ["lib"]

  spec.add_dependency "actioncable", ">= 8.0"
  spec.add_dependency "actionpack", ">= 8.0"
  spec.add_dependency "railties", ">= 8.0"
  spec.add_dependency "quicsilver", "~> 0.6.0"
  # Required directly: the Rack adapter's log is routed through it (see Rails::Server).
  spec.add_dependency "console", "~> 1.0"
end
