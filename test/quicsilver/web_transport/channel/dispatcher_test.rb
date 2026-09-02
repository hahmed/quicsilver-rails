# frozen_string_literal: true

require "test_helper"
require "quicsilver/web_transport/channel"

# Routing for incoming WebTransport streams.
#
# A command is request/response: handle it, write one reply, close. A stream
# handler is long-lived and owns the stream for its lifetime. The dispatcher
# picks between them by message type and must never leave a stream open after
# an error, or the peer waits forever for a reply that is not coming.
class QuicsilverWebTransportChannelDispatcherTest < Minitest::Test
  Dispatcher = Quicsilver::WebTransport::Channel::Dispatcher
  Session = WebTransportDoubles::Session
  RawStream = WebTransportDoubles::RawStream

  class ReactionCommand
    def self.call(message) = { type: "event", emoji: message.fetch("emoji") }
  end

  class ExplodingCommand
    def self.call(_message) = raise(ArgumentError, "bad reaction")
  end

  class ActivityStream
    class << self
      attr_accessor :received

      def call(stream:, codec:, session:, message:)
        self.received = { codec: codec, session: session, message: message }
        stream.write_message codec.encode(type: "snapshot", open: session.open?)
        stream.close
      end
    end
  end

  def setup
    ActivityStream.received = nil
  end

  # === commands ===

  def test_routes_a_command_by_message_type
    raw_stream = RawStream.new(JSON.generate(type: "reaction", emoji: "🔥"))

    dispatcher.call(raw_stream)

    assert_equal [{ "type" => "event", "emoji" => "🔥" }], raw_stream.json_messages
  end

  def test_closes_the_stream_after_a_command
    raw_stream = RawStream.new(JSON.generate(type: "reaction", emoji: "🔥"))

    dispatcher.call(raw_stream)

    assert raw_stream.closed
  end

  def test_writes_exactly_one_reply_per_command
    raw_stream = RawStream.new(JSON.generate(type: "reaction", emoji: "🔥"))

    dispatcher.call(raw_stream)

    assert_equal 1, raw_stream.messages.size
  end

  # === long-lived streams ===

  def test_routes_a_stream_by_message_type
    raw_stream = RawStream.new(JSON.generate(type: "subscribe"))

    dispatcher.call(raw_stream)

    assert_equal [{ "type" => "snapshot", "open" => true }], raw_stream.json_messages
  end

  # Stream handlers need the session to broadcast, and the opening message for
  # arguments such as a room id or cursor.
  def test_stream_handlers_receive_session_codec_and_message
    dispatcher(session: session = Session.new)
      .call(RawStream.new(JSON.generate(type: "subscribe", since: 12)))

    received = ActivityStream.received
    assert_same session, received[:session]
    assert_equal Quicsilver::WebTransport::Codec::JSON, received[:codec]
    assert_equal({ "type" => "subscribe", "since" => 12 }, received[:message])
  end

  # === unknown types ===

  def test_unknown_type_returns_a_structured_error
    raw_stream = RawStream.new(JSON.generate(type: "nope"))

    dispatcher.call(raw_stream)

    assert_equal [{ "type" => "error", "error" => "Unknown WebTransport message type: nope" }],
      raw_stream.json_messages
  end

  def test_unknown_type_closes_the_stream
    raw_stream = RawStream.new(JSON.generate(type: "nope"))

    dispatcher.call(raw_stream)

    assert raw_stream.closed
  end

  # === failures ===

  def test_a_raising_command_reports_the_error_to_the_peer
    raw_stream = RawStream.new(JSON.generate(type: "explode"))

    dispatcher.call(raw_stream)

    assert_equal [{ "type" => "error", "error" => "bad reaction" }], raw_stream.json_messages
  end

  # The peer is blocked reading. Leaving the stream open on error strands it.
  def test_a_raising_command_still_closes_the_stream
    raw_stream = RawStream.new(JSON.generate(type: "explode"))

    dispatcher.call(raw_stream)

    assert raw_stream.closed
  end

  def test_malformed_payload_reports_the_error_and_closes
    raw_stream = RawStream.new("not json")

    dispatcher.call(raw_stream)

    assert raw_stream.closed
    assert_equal "error", raw_stream.json_messages.first["type"]
  end

  # === empty streams ===

  def test_a_stream_that_ends_before_a_message_is_closed_quietly
    raw_stream = RawStream.new

    dispatcher.call(raw_stream)

    assert raw_stream.closed
    assert_empty raw_stream.messages, "nothing to reply to"
  end

  private
    def dispatcher(session: Session.new)
      Dispatcher.new(
        commands: { "reaction" => ReactionCommand, "explode" => ExplodingCommand },
        streams: { "subscribe" => ActivityStream },
        codec: Quicsilver::WebTransport::Codec.resolve(:json),
        session: session
      )
    end
end
