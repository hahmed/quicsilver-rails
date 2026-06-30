# frozen_string_literal: true

require "test_helper"

class QuicsilverWebTransportTest < Minitest::Test
  Context = Struct.new(:webtransport, keyword_init: true)

  def test_from_env_reads_context
    session = Object.new
    env = { "quicsilver.context" => Context.new(webtransport: session) }

    assert_same session, Quicsilver::WebTransport.from_env(env)
  end

  def test_from_env_falls_back_to_legacy_key
    session = Object.new
    env = { "quicsilver.webtransport" => session }

    assert_same session, Quicsilver::WebTransport.from_env(env)
  end
end
