# frozen_string_literal: true

require "test_helper"

class QuicsilverRailsVersionTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Quicsilver::Rails::VERSION
  end
end
