# frozen_string_literal: true

require "test_helper"
require "action_view"
require "action_dispatch"

class MetaTagsHelperTest < Minitest::Test
  class View
    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::OutputSafetyHelper
    include Quicsilver::Rails::WebTransportCertificateHelper
    include Quicsilver::Rails::CableCredentialHelper
    include Quicsilver::Rails::MetaTagsHelper

    attr_reader :request

    def initialize(protocol, cookies: nil)
      ActionDispatch::Request.include(Quicsilver::Rails::RequestProtocol)
      @request = ActionDispatch::Request.new({ "SERVER_PROTOCOL" => protocol, "HTTP_COOKIE" => cookies }.compact)
    end
  end

  Certificate = Struct.new(:sha256)

  def run(...)
    Quicsilver::Rails::DevWebTransportCertificate.stub(:fetch, Certificate.new("pinned-hash")) { super }
  end

  def test_an_http3_page_gets_the_certificate_cable_marker_and_credential
    html = View.new("HTTP/3").quicsilver_meta_tags(cable_credential: "abc")

    assert_includes html, %(<meta name="quicsilver-webtransport-certificate-sha256" content="pinned-hash">)
    assert_includes html, %(<meta name="quicsilver-cable" content="webtransport">)
    assert_includes html, %(<meta name="quicsilver-cable-credential" content="abc">)
  end

  def test_an_http3_page_without_a_credential_still_gets_the_marker
    html = View.new("HTTP/3").quicsilver_meta_tags

    assert_includes html, "quicsilver-cable"
    refute_includes html, "quicsilver-cable-credential"
  end

  def test_a_tcp_page_gets_nothing
    assert_empty View.new("HTTP/1.1").quicsilver_meta_tags(cable_credential: "abc")
  end

  def test_an_http3_page_carries_its_allowlisted_cookies_for_the_cable
    with_cookie_bridge do |bridge|
      html = View.new("HTTP/3", cookies: "session_token=signed; theme=dark").quicsilver_meta_tags
      token = html[/name="quicsilver-cable-cookies" content="([^"]+)"/, 1]

      assert_equal "session_token=signed", bridge.read(CGI.unescapeHTML(token))
    end
  end

  def test_no_cookie_tag_without_an_allowlisted_cookie_or_over_tcp
    with_cookie_bridge do
      refute_includes View.new("HTTP/3", cookies: "theme=dark").quicsilver_meta_tags, "quicsilver-cable-cookies"
      assert_empty View.new("HTTP/1.1", cookies: "session_token=signed").quicsilver_meta_tags
    end
  end

  private
    def with_cookie_bridge
      previous = Quicsilver::ActionCable.cookie_bridge
      bridge = Quicsilver::ActionCable::CookieBridge.new(secret: "s" * 32, names: %w[session_token])
      Quicsilver::ActionCable.cookie_bridge = bridge
      yield bridge
    ensure
      Quicsilver::ActionCable.cookie_bridge = previous
    end
end
