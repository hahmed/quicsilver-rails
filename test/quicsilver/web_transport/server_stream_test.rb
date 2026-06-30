# frozen_string_literal: true

require "test_helper"

class QuicsilverWebTransportServerStreamTest < Minitest::Test
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

    def each_stream
      @streams.each { |stream| yield stream }
    end

    def close
      @closed = true
    end

    def accepted?
      @accepted
    end
  end

  Context = Struct.new(:webtransport, keyword_init: true)

  class CompletionEndpoint < Quicsilver::WebTransport::ServerStream
    codec :json

    def perform(request)
      [
        { token: request.fetch("prompt") },
        { token: "done" }
      ]
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

  private

  def frame(message)
    [message.bytesize].pack("N") + message
  end

  def wait_until(timeout: 1)
    deadline = Time.now + timeout
    sleep 0.01 until yield || Time.now > deadline
  end
end
