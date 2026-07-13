# frozen_string_literal: true

require "test_helper"

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

    def close
      @closed = true
    end
  end

  class Session
    attr_reader :accepted, :closed

    def initialize(*streams)
      @streams = streams
      @accepted = false
      @closed = false
    end

    def accept!
      @accepted = true
    end

    def on_stream(&block)
      @streams.each(&block)
    end

    def on_close(&block)
      @close_callback = block
    end

    def close
      @closed = true
      @close_callback&.call
    end

    def open?
      !@closed
    end

    def accepted?
      @accepted
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
    session = Session.new(raw_stream)
    endpoint = EchoEndpoint.new("quicsilver.context" => Context.new(webtransport: session))

    assert_equal [200, {}, []], endpoint.call
    wait_until { session.closed }

    assert session.accepted
    assert raw_stream.closed
    assert_equal [{ "text" => "one" }, { "text" => "two" }], endpoint.received
    assert_equal [
      frame(JSON.generate(echo: "one")),
      frame(JSON.generate(echo: "two"))
    ], raw_stream.writes
  end

  def test_nil_return_writes_no_response
    raw_stream = RawStream.new('{"text":"one"}')
    session = Session.new(raw_stream)
    endpoint = SinkEndpoint.new("quicsilver.context" => Context.new(webtransport: session))

    assert_equal [200, {}, []], endpoint.call
    wait_until { session.closed }

    assert_equal [{ "text" => "one" }], endpoint.received
    assert_empty raw_stream.writes
  end

  private

  def frame(message)
    [message.bytesize].pack("N") + message
  end

  def wait_until(timeout: 1)
    deadline = Time.now + timeout
    sleep 0.01 until yield || Time.now > deadline
  end
end
