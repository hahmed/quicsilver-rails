# frozen_string_literal: true

require "test_helper"
require "quicsilver/server/web_transport_session"

class QuicsilverWebTransportMessageStreamEndpointTest < Minitest::Test
  class RawStream
    attr_reader :writes, :closed

    def initialize(*messages)
      @reads = Queue.new
      messages.each do |message|
        message = message.to_s.b
        @reads << [message.bytesize].pack("N") + message
      end
      @reads.close
      @writes = []
      @closed = false
    end

    def read
      @reads.pop
    end

    def write(data)
      @writes << data
    end

    def send(data, fin: false)
      @writes << data
      @closed = true if fin
      true
    end

    def close
      @closed = true
    end
  end

  class SessionStream
    attr_reader :stream_id, :stream_handle, :writes

    def initialize(stream_id: 0, stream_handle: 99_999)
      @stream_id = stream_id
      @stream_handle = stream_handle
      @writes = []
    end

    def send(data, fin: false)
      @writes << [data, fin]
      true
    end

    def reset(_code)
      true
    end
  end

  Context = Struct.new(:webtransport, keyword_init: true)

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
    session = build_session
    endpoint = EchoEndpoint.new("quicsilver.context" => Context.new(webtransport: session))

    assert_equal [200, {}, []], endpoint.call
    session.add_stream(raw_stream, 4)
    wait_until { raw_stream.closed }

    assert session.accepted?
    assert raw_stream.closed
    assert_equal [{ "text" => "one" }, { "text" => "two" }], endpoint.received
    assert_equal [
      frame(JSON.generate(echo: "one")),
      frame(JSON.generate(echo: "two"))
    ], raw_stream.writes
  end

  def test_nil_return_writes_no_response
    raw_stream = RawStream.new('{"text":"one"}')
    session = build_session
    endpoint = SinkEndpoint.new("quicsilver.context" => Context.new(webtransport: session))

    assert_equal [200, {}, []], endpoint.call
    session.add_stream(raw_stream, 4)
    wait_until { raw_stream.closed }

    assert_equal [{ "text" => "one" }], endpoint.received
    assert_empty raw_stream.writes
  end

  private

  def build_session
    Quicsilver::Server::WebTransportSession.new(
      connection: Object.new,
      stream: SessionStream.new,
      headers: {
        ":method" => "CONNECT",
        ":protocol" => "webtransport",
        ":scheme" => "https",
        ":authority" => "localhost:3000",
        ":path" => "/echo"
      }
    )
  end

  def frame(message)
    [message.bytesize].pack("N") + message
  end

  def wait_until(timeout: 1)
    deadline = Time.now + timeout
    sleep 0.01 until yield || Time.now > deadline
  end
end
