# frozen_string_literal: true

require "test_helper"
require "action_view"
require "action_dispatch"

class CableCredentialHelperTest < Minitest::Test
  class View
    include ActionView::Helpers::TagHelper
    include Quicsilver::Rails::CableCredentialHelper

    attr_reader :request

    def initialize(protocol)
      ActionDispatch::Request.include(Quicsilver::Rails::RequestProtocol)
      @request = ActionDispatch::Request.new("SERVER_PROTOCOL" => protocol)
    end
  end

  def test_renders_when_the_page_arrived_over_http3
    assert_includes View.new("HTTP/3").quicsilver_cable_credential_meta_tag("abc"), %(content="abc")
  end

  def test_renders_nothing_when_the_page_arrived_over_tcp
    assert_nil View.new("HTTP/1.1").quicsilver_cable_credential_meta_tag("abc")
  end

  def test_renders_nothing_without_a_credential
    assert_nil View.new("HTTP/3").quicsilver_cable_credential_meta_tag(nil)
  end
end
