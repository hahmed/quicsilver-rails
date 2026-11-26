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

  # The exception's message can carry SQL, record data or paths; the peer must not see it.
  def test_a_raising_command_answers_the_peer_without_the_exception_text
    raw_stream = RawStream.new(JSON.generate(type: "explode"))

    dispatcher.call(raw_stream)

    assert_equal [{ "type" => "error", "error" => "Internal error" }], raw_stream.json_messages
  end

  def test_a_raising_command_is_reported_to_the_apps_error_reporter
    reports = capture_error_reports { dispatcher.call(RawStream.new(JSON.generate(type: "explode"))) }

    assert_equal 1, reports.size
    assert_instance_of ArgumentError, reports.first[:error]
    assert_equal "bad reaction", reports.first[:error].message
    assert reports.first[:handled]
    assert_equal "quicsilver.webtransport", reports.first[:source]
  end

  # A reply that cannot be written must not replace the error being answered.
  def test_a_failing_error_reply_does_not_replace_the_reported_error
    raw_stream = UnwritableStream.new(JSON.generate(type: "explode"))

    reports = capture_error_reports { dispatcher.call(raw_stream) }

    assert_instance_of ArgumentError, reports.first[:error]
  end

  # The peer is blocked reading. Leaving the stream open on error strands it.
  def test_a_raising_command_still_closes_the_stream
    raw_stream = RawStream.new(JSON.generate(type: "explode"))

    dispatcher.call(raw_stream)

    assert raw_stream.closed
  end

  # A payload that cannot be decoded is the peer's mistake, not the app's: answered, not reported.
  def test_a_malformed_payload_is_answered_and_not_reported
    raw_stream = RawStream.new("not json")

    reports = capture_error_reports { dispatcher.call(raw_stream) }

    assert raw_stream.closed
    assert_equal [{ "type" => "error", "error" => "Malformed message" }], raw_stream.json_messages
    assert_empty reports
  end

  # === peer resets ===

  # A reset is how a peer disconnects mid-stream. Writing to it would raise and bury the cause.
  def test_a_peer_reset_is_neither_answered_nor_reported
    raw_stream = ResetStream.new

    reports = capture_error_reports { dispatcher.call(raw_stream) }

    assert_empty raw_stream.writes
    assert_empty reports
  end

  # === empty streams ===

  def test_a_stream_that_ends_before_a_message_is_closed_quietly
    raw_stream = RawStream.new

    dispatcher.call(raw_stream)

    assert raw_stream.closed
    assert_empty raw_stream.messages, "nothing to reply to"
  end

  # The peer reset the stream before sending anything.
  class ResetStream < RawStream
    def read = raise(Quicsilver::Server::WebTransportStream::ResetError.new(0x10c))
  end

  class UnwritableStream < RawStream
    def write(_data) = raise(IOError, "Stream is closed for writing")
  end

  class ErrorSubscriber
    attr_reader :reports

    def initialize = @reports = []
    def report(error, handled:, severity:, context:, source: nil)
      @reports << { error: error, handled: handled, source: source }
    end
  end

  private
    def capture_error_reports
      subscriber = ErrorSubscriber.new
      ::Rails.error.subscribe(subscriber)
      yield
      subscriber.reports
    ensure
      ::Rails.error.unsubscribe(subscriber)
    end

    def dispatcher(session: Session.new)
      Dispatcher.new(
        commands: { "reaction" => ReactionCommand, "explode" => ExplodingCommand },
        streams: { "subscribe" => ActivityStream },
        codec: Quicsilver::WebTransport::Codec.resolve(:json),
        session: session
      )
    end
end
