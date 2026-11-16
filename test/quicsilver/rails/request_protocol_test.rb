# frozen_string_literal: true

require "test_helper"
require "action_dispatch"

class RequestProtocolTest < Minitest::Test
  def setup
    ActionDispatch::Request.include(Quicsilver::Rails::RequestProtocol)
  end

  def test_http3_when_quicsilver_served_the_request
    assert ActionDispatch::Request.new("SERVER_PROTOCOL" => "HTTP/3").http3?
  end

  def test_not_http3_over_tcp
    refute ActionDispatch::Request.new("SERVER_PROTOCOL" => "HTTP/1.1").http3?
    refute ActionDispatch::Request.new("SERVER_PROTOCOL" => "HTTP/2").http3?
    refute ActionDispatch::Request.new({}).http3?
  end
end
