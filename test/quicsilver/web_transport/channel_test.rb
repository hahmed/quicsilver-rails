# frozen_string_literal: true

require "test_helper"
require "quicsilver/web_transport/channel"

class QuicsilverWebTransportChannelTest < Minitest::Test
  class RawStream
    attr_reader :writes, :closed

    def initialize(message)
      message = message.to_s.b
      @reads = Queue.new
      @reads << [message.bytesize].pack("N") + message
      @reads.close
      @writes = []
      @closed = false
    end

    def read
      @reads.pop
    rescue ClosedQueueError
      nil
    end

    def write(data)
      @writes << data
    end

    def close
      @closed = true
    end
  end

  class Session
    def open?
      true
    end
  end

  class ReactionCommand
    def self.call(message)
      { type: "event", emoji: message.fetch("emoji") }
    end
  end

  class ActivityStream
    def self.call(stream:, codec:, session:, message:)
      stream.write_message codec.encode(type: "snapshot", requested: message.fetch("type"), open: session.open?)
      stream.close
    end
  end

  class DropChannel < Quicsilver::WebTransport::Channel
    attr_reader :datagrams

    def initialize(*)
      super
      @datagrams = []
    end

    datagram do |packet|
      datagrams << packet
    end
  end

  def test_dispatches_command_streams_by_message_type
    raw_stream = RawStream.new(JSON.generate(type: "reaction", emoji: "🔥"))

    dispatcher.call(raw_stream)

    assert raw_stream.closed
    assert_equal [{ "type" => "event", "emoji" => "🔥" }], written_messages(raw_stream)
  end

  def test_dispatches_live_streams_by_message_type
    raw_stream = RawStream.new(JSON.generate(type: "subscribe"))

    dispatcher.call(raw_stream)

    assert raw_stream.closed
    assert_equal [{ "type" => "snapshot", "requested" => "subscribe", "open" => true }], written_messages(raw_stream)
  end

  def test_unknown_message_type_returns_structured_error
    raw_stream = RawStream.new(JSON.generate(type: "unknown"))

    dispatcher.call(raw_stream)

    assert raw_stream.closed
    assert_equal [{ "type" => "error", "error" => "Unknown WebTransport message type: unknown" }], written_messages(raw_stream)
  end

  def test_handles_datagrams_in_channel_context
    channel = DropChannel.new({})

    channel.send(:handle_datagram, "hype")

    assert_equal ["hype"], channel.datagrams
  end

  private
    def dispatcher
      Quicsilver::WebTransport::Channel::Dispatcher.new(
        commands: { "reaction" => ReactionCommand },
        streams: { "subscribe" => ActivityStream },
        codec: Quicsilver::WebTransport::Codec.resolve(:json),
        session: Session.new
      )
    end

    def written_messages(raw_stream)
      raw_stream.writes.map do |frame|
        length = frame.byteslice(0, 4).unpack1("N")
        JSON.parse(frame.byteslice(4, length))
      end
    end
end
