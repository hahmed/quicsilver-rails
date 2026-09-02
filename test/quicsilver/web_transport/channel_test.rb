# frozen_string_literal: true

require "test_helper"
require "quicsilver/web_transport/channel"

class QuicsilverWebTransportChannelTest < Minitest::Test
  RawStream = WebTransportDoubles::RawStream

  Session = WebTransportDoubles::Session

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
    assert_equal [{ "type" => "event", "emoji" => "🔥" }], raw_stream.json_messages
  end

  def test_dispatches_live_streams_by_message_type
    raw_stream = RawStream.new(JSON.generate(type: "subscribe"))

    dispatcher.call(raw_stream)

    assert raw_stream.closed
    assert_equal [{ "type" => "snapshot", "requested" => "subscribe", "open" => true }], raw_stream.json_messages
  end

  def test_unknown_message_type_returns_structured_error
    raw_stream = RawStream.new(JSON.generate(type: "unknown"))

    dispatcher.call(raw_stream)

    assert raw_stream.closed
    assert_equal [{ "type" => "error", "error" => "Unknown WebTransport message type: unknown" }], raw_stream.json_messages
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
end
