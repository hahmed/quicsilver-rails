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
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "actioncable", ">= 7.1"
  spec.add_dependency "actionpack", ">= 7.1"
  spec.add_dependency "railties", ">= 7.1"
  spec.add_dependency "quicsilver", ">= 0.1.0"
end
