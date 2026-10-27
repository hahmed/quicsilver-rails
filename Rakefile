# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

desc "Run the browser-side tests under node"
task :test_js do
  if system("node --version > /dev/null 2>&1")
    # --import registers a resolver for the bare "quicsilver/*" specifiers importmap-rails gives the
    # browser, so the shipped source runs here unmodified.
    sh "node --test --import ./test/javascript/register_importmap.mjs test/javascript/*_test.mjs"
  else
    # Reported rather than skipped silently: these cover framing the Ruby side cannot see.
    warn "node not found, skipping the browser-side tests"
  end
end

task default: [ :test, :test_js ]
