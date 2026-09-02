# frozen_string_literal: true

require "test_helper"

# Contract for long-lived channel streams.
#
# The dispatcher passes context as keyword arguments. The whole point of this
# base class is that adding a key later must not break existing handlers, so
# most of these tests are about tolerating change rather than behaviour today.
class QuicsilverWebTransportStreamHandlerTest < Minitest::Test
  StreamHandler = Quicsilver::WebTransport::StreamHandler
  RawStream = WebTransportDoubles::RawStream
  Session = WebTransportDoubles::Session

  class Echo < StreamHandler
    def call
      while (incoming = read)
        write(echo: incoming.fetch("text"))
      end
      close
    end
  end

  class Snapshot < StreamHandler
    def call
      write(type: "snapshot", requested: message&.fetch("type", nil), open: session&.open?)
      close
    end
  end

  class Recorder < StreamHandler
    class << self
      attr_accessor :seen
    end

    def call
      self.class.seen = { session: session, message: message, context: context }
    end
  end

  def setup
    Recorder.seen = nil
  end

  # === the reason this class exists ===

  # A plain class implementing self.call has to write ** by hand or break the
  # moment the dispatcher passes a new key. Subclasses get that for free.
  def test_absorbs_unknown_context_keys
    raw_stream = RawStream.new

    Snapshot.call(
      stream: framed(raw_stream),
      codec: codec,
      session: Session.new,
      message: { "type" => "subscribe" },
      something_added_later: 42
    )

    assert_equal "subscribe", raw_stream.json_messages.first["requested"]
  end

  def test_unknown_keys_are_available_as_context
    Recorder.call(stream: framed(RawStream.new), codec: codec, tenant: "acme")

    assert_equal({ tenant: "acme" }, Recorder.seen[:context])
  end

  def test_session_and_message_are_optional
    Recorder.call(stream: framed(RawStream.new), codec: codec)

    assert_nil Recorder.seen[:session]
    assert_nil Recorder.seen[:message]
  end

  # === wiring ===

  def test_call_builds_an_instance_and_runs_it
    raw_stream = RawStream.new

    Snapshot.call(stream: framed(raw_stream), codec: codec, session: Session.new)

    assert_equal "snapshot", raw_stream.json_messages.first["type"]
  end

  def test_exposes_the_opening_message
    Recorder.call(stream: framed(RawStream.new), codec: codec, message: { "since" => 12 })

    assert_equal({ "since" => 12 }, Recorder.seen[:message])
  end

  def test_exposes_the_session
    session = Session.new
    Recorder.call(stream: framed(RawStream.new), codec: codec, session: session)

    assert_same session, Recorder.seen[:session]
  end

  # === helpers ===

  def test_write_encodes_through_the_codec
    raw_stream = RawStream.new

    Snapshot.call(stream: framed(raw_stream), codec: codec, session: Session.new)

    assert_equal [{ "type" => "snapshot", "requested" => nil, "open" => true }],
      raw_stream.json_messages
  end

  def test_read_decodes_each_message_until_the_peer_is_done
    raw_stream = RawStream.new('{"text":"one"}', '{"text":"two"}')

    Echo.call(stream: framed(raw_stream), codec: codec)

    assert_equal [{ "echo" => "one" }, { "echo" => "two" }], raw_stream.json_messages
  end

  def test_read_returns_nil_when_the_peer_sends_nothing
    raw_stream = RawStream.new

    Echo.call(stream: framed(raw_stream), codec: codec)

    assert_empty raw_stream.messages
  end

  def test_close_closes_the_stream
    raw_stream = RawStream.new

    Snapshot.call(stream: framed(raw_stream), codec: codec, session: Session.new)

    assert raw_stream.closed
  end

  # === abstract contract ===

  def test_call_is_abstract
    handler = StreamHandler.new(stream: framed(RawStream.new), codec: codec)

    error = assert_raises(NotImplementedError) { handler.call }
    assert_match(/must implement #call/, error.message)
  end

  private
    def framed(raw_stream)
      Quicsilver::WebTransport::FramedStream.new(raw_stream)
    end

    def codec
      Quicsilver::WebTransport::Codec.resolve(:json)
    end
end
