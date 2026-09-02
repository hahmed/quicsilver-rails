# frozen_string_literal: true

require "test_helper"

class QuicsilverWebTransportMessageStreamEndpointTest < Minitest::Test
  RawStream = WebTransportDoubles::RawStream

  class EchoEndpoint < Quicsilver::WebTransport::MessageStreamEndpoint
    codec :json

    attr_reader :received

    def initialize(*)
      super
      @received = []
    end

    def receive(message)
      @received << message
      { echo: message.fetch("text") }
    end
  end

  class SinkEndpoint < Quicsilver::WebTransport::MessageStreamEndpoint
    codec :json

    attr_reader :received

    def initialize(*)
      super
      @received = []
    end

    def receive(message)
      @received << message
      nil
    end
  end

  def test_reads_many_messages_and_writes_response_for_each_non_nil_return
    raw_stream = RawStream.new('{"text":"one"}', '{"text":"two"}')
    endpoint = EchoEndpoint.new({})

    endpoint.handle_stream(raw_stream)

    assert raw_stream.closed
    assert_equal [{ "text" => "one" }, { "text" => "two" }], endpoint.received
    assert_equal [
      frame(JSON.generate(echo: "one")),
      frame(JSON.generate(echo: "two"))
    ], raw_stream.writes
  end

  def test_nil_return_writes_no_response
    raw_stream = RawStream.new('{"text":"one"}')
    endpoint = SinkEndpoint.new({})

    endpoint.handle_stream(raw_stream)

    assert raw_stream.closed
    assert_equal [{ "text" => "one" }], endpoint.received
    assert_empty raw_stream.writes
  end
end
