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

  # Configuration shared through a base class has to reach its subclasses.
  class InsertOperationEndpoint < ApplyOperationEndpoint; end

  Operation = Struct.new(:attributes) do
    def op = attributes.fetch("op")
  end

  class TypedEndpoint < Quicsilver::WebTransport::RpcEndpoint
    codec :json
    receives Operation

    def perform(operation) = { op: operation.op }
  end

  class TypedSubclassEndpoint < TypedEndpoint; end

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

  def test_a_subclass_keeps_its_parents_codec
    assert_equal [frame(JSON.generate(status: "ok", op: "insert"))], writes_for(InsertOperationEndpoint, '{"op":"insert"}')
  end

  def test_a_subclass_keeps_its_parents_message_type
    assert_equal [frame(JSON.generate(op: "insert"))], writes_for(TypedSubclassEndpoint, '{"op":"insert"}')
  end

  private
    def writes_for(endpoint_class, request)
      raw_stream = RawStream.new(request)
      session = Session.new(raw_stream)
      endpoint_class.new("quicsilver.context" => Context.new(webtransport: session)).call
      wait_until { session.closed }
      raw_stream.writes
    end
end
