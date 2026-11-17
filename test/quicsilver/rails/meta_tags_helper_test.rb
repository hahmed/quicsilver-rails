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

    def initialize(protocol)
      ActionDispatch::Request.include(Quicsilver::Rails::RequestProtocol)
      @request = ActionDispatch::Request.new("SERVER_PROTOCOL" => protocol)
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

  def test_rails_without_the_socket_seam_gets_no_cable_tags
    Quicsilver::ActionCable.stub(:available?, false) do
      html = View.new("HTTP/3").quicsilver_meta_tags(cable_credential: "abc")

      refute_includes html, "quicsilver-cable"
      assert_includes html, "pinned-hash", "WebTransport endpoints still need the certificate on older Rails"
    end
  end
end
