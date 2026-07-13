# frozen_string_literal: true

require "test_helper"

class QuicsilverWebTransportDatagramEndpointTest < Minitest::Test
  class Session
    attr_reader :accepted, :closed

    def initialize(*datagrams)
      @datagrams = datagrams
      @accepted = false
      @closed = false
    end

    def accept!
      @accepted = true
    end

    def on_datagram(&block)
      @datagrams.each(&block)
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
    session = Session.new('{"x":1}', '{"x":2}')
    endpoint = CursorEndpoint.new("quicsilver.context" => Context.new(webtransport: session))

    assert_equal [200, {}, []], endpoint.call
    wait_until { session.closed }

    assert session.accepted
    assert_equal [{ "x" => 1 }, { "x" => 2 }], endpoint.received
  end

  private

  def wait_until(timeout: 1)
    deadline = Time.now + timeout
    sleep 0.01 until yield || Time.now > deadline
  end
end
