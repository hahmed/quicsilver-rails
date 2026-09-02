# frozen_string_literal: true

require "test_helper"

class QuicsilverWebTransportRpcEndpointTest < Minitest::Test
  RawStream = WebTransportDoubles::RawStream
  Session = WebTransportDoubles::Session
  Context = WebTransportDoubles::Context

  class ApplyOperationEndpoint < Quicsilver::WebTransport::RpcEndpoint
    codec :json

    def perform(request)
      { status: "ok", op: request.fetch("op") }
    end
  end

  def test_reads_one_request_and_writes_one_response
    raw_stream = RawStream.new('{"op":"insert"}')
    session = Session.new(raw_stream)
    endpoint = ApplyOperationEndpoint.new("quicsilver.context" => Context.new(webtransport: session))

    assert_equal [200, {}, []], endpoint.call
    wait_until { session.closed }

    assert session.accepted
    assert raw_stream.closed
    assert_equal [frame(JSON.generate(status: "ok", op: "insert"))], raw_stream.writes
  end
end
