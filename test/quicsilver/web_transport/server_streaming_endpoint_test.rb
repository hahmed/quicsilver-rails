# frozen_string_literal: true

require "test_helper"

class QuicsilverWebTransportServerStreamingEndpointTest < Minitest::Test
  RawStream = WebTransportDoubles::RawStream
  Session = WebTransportDoubles::Session
  Context = WebTransportDoubles::Context

  class CompletionEndpoint < Quicsilver::WebTransport::ServerStreamingEndpoint
    codec :json

    def perform(request)
      [
        { token: request.fetch("prompt") },
        { token: "done" }
      ]
    end
  end

  class HashResponseEndpoint < Quicsilver::WebTransport::ServerStreamingEndpoint
    codec :json

    def perform(request)
      { token: request.fetch("prompt") }
    end
  end

  def test_reads_one_request_and_streams_responses
    raw_stream = RawStream.new('{"prompt":"hi"}')
    session = Session.new(raw_stream)
    endpoint = CompletionEndpoint.new("quicsilver.context" => Context.new(webtransport: session))

    assert_equal [200, {}, []], endpoint.call
    wait_until { session.closed }

    assert session.accepted
    assert raw_stream.closed
    assert_equal [
      frame(JSON.generate(token: "hi")),
      frame(JSON.generate(token: "done"))
    ], raw_stream.writes
  end

  def test_hash_return_value_is_one_response_not_key_value_stream
    raw_stream = RawStream.new('{"prompt":"hi"}')
    session = Session.new(raw_stream)
    endpoint = HashResponseEndpoint.new("quicsilver.context" => Context.new(webtransport: session))

    assert_equal [200, {}, []], endpoint.call
    wait_until { session.closed }

    assert_equal [frame(JSON.generate(token: "hi"))], raw_stream.writes
  end
end
