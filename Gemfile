# frozen_string_literal: true

source "https://rubygems.org"

# Specify gem dependencies in quicsilver-rails.gemspec.
gemspec

github "rails/rails", branch: "main" do
  gem "rails"
  gem "actioncable"
  gem "actionpack"
  gem "actionview"
  gem "activesupport"
  gem "railties"
end

# Track Quicsilver browser-compatible WebTransport branch while this integration is experimental.
gem "quicsilver", github: "hahmed/quicsilver", branch: "webtransport-capsule-behavior"

gem "irb"
gem "rake", "~> 13.0"
gem "minitest", "~> 5.16"
