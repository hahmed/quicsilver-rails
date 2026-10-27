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

gem "quicsilver", github: "hahmed/quicsilver", branch: "main"
# The pinned Rails main calls JSON.parse(json, options) positionally, which json 3.1 removed.
# Later Rails main fixes it but needs Ruby 4.0; hold json back until the Ruby bump.
gem "json", "< 3.1"

gem "irb"
gem "rake", "~> 13.0"
gem "minitest", "~> 5.16"
