# frozen_string_literal: true

require "test_helper"
require "quicsilver/web_transport/endpoint"
require "quicsilver/web_transport/channel"

# Lifecycle contract for the Endpoint base class.
#
# Cleanup after an endpoint finishes — #disconnect, then closing the session —
# must survive a subclass overriding #run. Every real endpoint overrides it,
# including Channel, so keeping cleanup in the same method as the abstract hook
# meant it was silently dropped for all of them: apps never heard that a peer
# had gone, and long-lived membership leaked for the life of the process.
class QuicsilverWebTransportEndpointTest < Minitest::Test
  Session = WebTransportDoubles::Session

  # Records lifecycle order so tests assert on sequence, not just presence.
  class RecordingEndpoint < Quicsilver::WebTransport::Endpoint
    def events = @events ||= []

    def connect = events << :connect
    def disconnect = events << :disconnect

    private
      def run = events << :run
  end

  class FailingEndpoint < RecordingEndpoint
    private
      def run
        events << :run
        raise "boom"
      end
  end

  class SelfClosingEndpoint < RecordingEndpoint
    private
      def run
        events << :run
        session.close
      end
  end

  # The real-world case: Channel defines its own #run, which is how the bug
  # reached production.
  class RecordingChannel < Quicsilver::WebTransport::Channel
    def events = @events ||= []

    def connect = events << :connect
    def disconnect = events << :disconnect
  end

  # === cleanup survives subclassing (the regression) ===

  def test_disconnect_runs_when_a_subclass_overrides_run
    endpoint = RecordingEndpoint.new(env)
    endpoint.call

    wait_until { endpoint.events.include?(:disconnect) }
    assert_equal [:connect, :run, :disconnect], endpoint.events
  end

  def test_session_is_closed_when_a_subclass_overrides_run
    session = Session.new
    RecordingEndpoint.new(env(session)).call

    wait_until { session.closed }
    assert session.closed
  end

  # Channel#run blocks in wait_for_session_close, so cleanup only runs once the
  # peer disconnects. That is the shape the bug hid behind: a long-lived
  # channel whose #disconnect never fired when the peer went away.
  def test_disconnect_runs_for_a_channel_subclass_when_the_peer_disconnects
    session = Session.new
    channel = RecordingChannel.new(env(session))
    channel.call

    session.close

    wait_until { channel.events.include?(:disconnect) }
    assert_includes channel.events, :disconnect,
      "Channel overrides #run, so it must still receive #disconnect"
  end

  def test_a_channel_stays_open_until_the_peer_disconnects
    session = Session.new
    channel = RecordingChannel.new(env(session))
    channel.call

    wait_until(timeout: 0.1) { channel.events.include?(:disconnect) }
    refute_includes channel.events, :disconnect,
      "a live channel must not tear down while the peer is still connected"
  end

  # === cleanup survives failure ===

  def test_disconnect_runs_when_run_raises
    endpoint = FailingEndpoint.new(env)
    endpoint.call

    wait_until { endpoint.events.include?(:disconnect) }
    assert_equal [:connect, :run, :disconnect], endpoint.events
  end

  def test_session_is_closed_when_run_raises
    session = Session.new
    FailingEndpoint.new(env(session)).call

    wait_until { session.closed }
    assert session.closed
  end

  def test_an_endpoint_that_closes_its_own_session_is_not_closed_twice
    session = Session.new
    closes = 0
    session.define_singleton_method(:close) do
      closes += 1
      @closed = true
    end

    SelfClosingEndpoint.new(env(session)).call

    wait_until { closes.positive? }
    assert_equal 1, closes, "open? guards the second close"
  end

  # === accept lifecycle ===

  def test_connect_runs_before_the_session_is_accepted
    order = []
    session = Session.new
    session.define_singleton_method(:accept!) { order << :accept; @accepted = true }

    endpoint = Class.new(RecordingEndpoint) do
      define_method(:connect) { order << :connect }
    end.new(env(session))
    endpoint.call

    wait_until { session.closed }
    assert_equal [:connect, :accept], order
  end

  def test_accepts_the_session
    session = Session.new
    RecordingEndpoint.new(env(session)).call

    assert session.accepted
  end

  def test_returns_200_once_accepted
    status, _headers, _body = RecordingEndpoint.new(env).call

    assert_equal 200, status
  end

  # === no session ===

  def test_returns_404_without_a_session
    status, headers, body = RecordingEndpoint.new({}).call

    assert_equal 404, status
    assert_equal ["WebTransport session not found"], body
    assert_match(/text\/plain/, headers["content-type"])
  end

  def test_does_not_run_without_a_session
    endpoint = RecordingEndpoint.new({})
    endpoint.call

    assert_empty endpoint.events
  end

  # === session discovery ===

  def test_finds_the_session_under_the_legacy_env_key
    session = Session.new
    endpoint = RecordingEndpoint.new("quicsilver.webtransport" => session)

    assert_same session, endpoint.session
  end

  def test_prefers_the_session_from_the_quicsilver_context
    context_session = Session.new
    context = Struct.new(:webtransport).new(context_session)
    endpoint = RecordingEndpoint.new(
      "quicsilver.context" => context,
      "quicsilver.webtransport" => Session.new
    )

    assert_same context_session, endpoint.session
  end

  # === abstract contract ===

  def test_run_is_abstract_on_the_base_class
    endpoint = Quicsilver::WebTransport::Endpoint.new(env)

    error = assert_raises(NotImplementedError) { endpoint.send(:run) }
    assert_match(/must implement #run/, error.message)
  end

  def test_connect_and_disconnect_are_optional
    endpoint = Quicsilver::WebTransport::Endpoint.new(env)

    assert_nil endpoint.connect
    assert_nil endpoint.disconnect
  end

  # A failure before accept! must reject rather than leave the peer hanging.
  def test_rejects_when_connect_raises
    session = Session.new
    endpoint = Class.new(Quicsilver::WebTransport::Endpoint) do
      def connect = raise("nope")
      private def run = nil
    end.new(env(session))

    assert_raises(RuntimeError) { endpoint.call }
    assert_equal 500, session.rejected_with
  end

  def test_does_not_reject_a_session_already_accepted
    session = Session.new
    session.accept!
    endpoint = Class.new(Quicsilver::WebTransport::Endpoint) do
      def connect = raise("nope")
      private def run = nil
    end.new(env(session))

    assert_raises(RuntimeError) { endpoint.call }
    assert_nil session.rejected_with
  end

  private
    def env(session = Session.new)
      { "quicsilver.webtransport" => session }
    end
end
