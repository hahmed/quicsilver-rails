# frozen_string_literal: true

require "test_helper"

class QuicsilverWebTransportDatagramEndpointTest < Minitest::Test
  Session = WebTransportDoubles::Session
  Context = WebTransportDoubles::Context

  class CursorEndpoint < Quicsilver::WebTransport::DatagramEndpoint
    codec :json

    attr_reader :received

    def initialize(*)
      super
      @received = []
    end

    def receive(message)
      @received << message
    end
  end

  def test_accepts_session_and_receives_decoded_datagrams
    session = Session.new(datagrams: ['{"x":1}', '{"x":2}'])
    endpoint = CursorEndpoint.new("quicsilver.context" => Context.new(webtransport: session))

    assert_equal [200, {}, []], endpoint.call
    wait_until { session.closed }

    assert session.accepted
    assert_equal [{ "x" => 1 }, { "x" => 2 }], endpoint.received
  end
end
