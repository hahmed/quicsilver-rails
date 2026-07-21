# frozen_string_literal: true

require "test_helper"

class ActionCableWebTransportSocketTest < Minitest::Test
  class EventTarget
    attr_reader :opened, :messages, :closed, :errors

    def initialize
      @opened = false
      @messages = []
      @closed = false
      @errors = []
    end

    def on_open
      @opened = true
    end

    def on_message(message)
      @messages << message
    end

    def on_close(*)
      @closed = true
    end

    def on_error(message)
      @errors << message
    end
  end

  class Session
    def initialize(stream)
      @stream = stream
      @closed = false
    end

    def accept!
      @accepted = true
    end

    def on_stream(&block)
      @on_stream = block
    end

    def deliver_stream
      @on_stream.call(@stream)
    end

    def open?
      !@closed
    end

    def close
      @closed = true
      @stream.close
    end
  end

  class Stream
    attr_reader :writes

    def initialize(*reads)
      @reads = Queue.new
      reads.each { |read| @reads << frame(read) }
      @reads.close
      @writes = []
    end

    def read
      @reads.pop
    end

    def write(message)
      @writes << message
    end

    def close
      @reads.close unless @reads.closed?
    end

    private

    def frame(message)
      message = message.to_s.b
      [message.bytesize].pack("N") + message
    end
  end

  Context = Struct.new(:webtransport, keyword_init: true)

  def test_possible_when_webtransport_session_is_present
    socket = build_socket

    assert socket.possible?
  end

  def test_rack_response_accepts_session_and_reads_messages
    stream = Stream.new("hello")
    session = Session.new(stream)
    target = EventTarget.new
    socket = build_socket(session: session, target: target)

    assert_equal [200, {}, []], socket.rack_response
    refute target.opened

    session.deliver_stream
    sleep 0.01

    assert target.opened
    assert_equal ["hello"], target.messages
    assert target.closed
  end

  def test_transmit_writes_to_webtransport_stream
    stream = Stream.new
    session = Session.new(stream)
    socket = build_socket(session: session)

    socket.rack_response
    session.deliver_stream

    assert socket.transmit("message")
    assert_equal [["message".bytesize].pack("N") + "message"], stream.writes
  end

  private

  def build_socket(session: Session.new(Stream.new), target: EventTarget.new)
    env = { "quicsilver.context" => Context.new(webtransport: session) }
    ::ActionCable::Server::Socket::WebTransport.new(env, target)
  end
end
