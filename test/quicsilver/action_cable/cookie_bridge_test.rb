# frozen_string_literal: true

require "test_helper"
require "active_support/testing/time_helpers"

class CookieBridgeTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  SECRET = "s" * 32
  CookieBridge = Quicsilver::ActionCable::CookieBridge

  def bridge(secret: SECRET, names: %w[session_token])
    CookieBridge.new(secret: secret, names: names)
  end

  FakeApp = Struct.new(:config, :key_generator)

  def fake_app(cable_cookies: nil)
    config = ActiveSupport::OrderedOptions.new
    config.quicsilver = ActiveSupport::OrderedOptions.new
    config.quicsilver.cable_cookies = cable_cookies
    config.session_options = { key: "_app_session" }
    FakeApp.new(config, ActiveSupport::KeyGenerator.new("secret", iterations: 1))
  end

  def parsed(header)
    ActionDispatch::Request.new("HTTP_COOKIE" => header).cookies
  end

  def test_carries_the_allowlisted_cookies_as_the_browser_sent_them
    signed = "eyJfcmFpbHMiOnsiZGF0YSI6MX19--3f2a%=/+"
    token = bridge.token_for("session_token" => signed, "theme" => "dark")

    assert_equal({ "session_token" => signed }, parsed(bridge.read(token)))
  end

  def test_issues_no_token_when_no_allowlisted_cookie_is_present
    assert_nil bridge.token_for("theme" => "dark")
    assert_nil bridge(names: nil).token_for("session_token" => "abc")
  end

  def test_rejects_a_token_it_did_not_issue
    token = bridge(secret: "o" * 32).token_for("session_token" => "abc")

    assert_nil bridge.read(token)
    assert_nil bridge.read("not-a-token")
    assert_nil bridge.read(nil)
  end

  # With no cable_cookies, the cookies Rails apps sign in with by default: the session cookie, and
  # session_id from Rails' authentication generator.
  def test_carries_the_apps_session_cookies_when_none_are_configured
    bridge = ::Rails.stub(:application, fake_app) { CookieBridge.from_rails }
    token = bridge.token_for("_app_session" => "blob", "session_id" => "42", "theme" => "dark")

    assert_equal({ "_app_session" => "blob", "session_id" => "42" }, parsed(bridge.read(token)))
  end

  def test_configured_cookies_replace_the_defaults
    bridge = ::Rails.stub(:application, fake_app(cable_cookies: %i[session_token])) { CookieBridge.from_rails }
    token = bridge.token_for("_app_session" => "blob", "session_token" => "signed")

    assert_equal({ "session_token" => "signed" }, parsed(bridge.read(token)))
  end

  def test_rejects_an_expired_token
    token = bridge.token_for("session_token" => "abc")

    travel(CookieBridge::EXPIRES_IN + 1) do
      assert_nil bridge.read(token)
    end
  end
end
