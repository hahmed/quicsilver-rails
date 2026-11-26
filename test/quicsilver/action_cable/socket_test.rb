# frozen_string_literal: true

require "test_helper"
require "stringio"

class QuicsilverActionCableSocketTest < Minitest::Test
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
    attr_reader :writes, :closed

    def initialize(*reads, open: false, reset_with: nil)
      @reset_with = reset_with
      @reads = Queue.new
      reads.each { |read| @reads << frame(read) }
      @reads.close unless open
      @writes = []
      @closed = false
    end

    def read
      message = @reads.pop
      raise Quicsilver::Server::WebTransportStream::ResetError.new(@reset_with) if message.nil? && @reset_with

      message
    end

    def write(message)
      @writes << message
    end

    def close
      @closed = true
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

  def test_a_stream_reset_because_the_session_ended_closes_without_an_error
    gone = Quicsilver::Protocol::WebTransport::SESSION_GONE
    session = Session.new(Stream.new("hello", reset_with: gone))
    target = EventTarget.new
    build_socket(session: session, target: target).rack_response

    session.deliver_stream
    sleep 0.01

    assert_equal ["hello"], target.messages
    assert target.closed
    assert_empty target.errors
  end

  def test_any_other_stream_reset_is_reported_as_an_error
    session = Session.new(Stream.new("hello", reset_with: 0x52e4a40fa8db))
    target = EventTarget.new
    build_socket(session: session, target: target).rack_response

    session.deliver_stream
    sleep 0.01

    assert target.closed
    assert_equal 1, target.errors.size
    assert_match(/WebTransport stream reset/, target.errors.first)
  end

  def test_a_second_stream_on_the_session_is_closed_not_left_hanging
    # Streams built with no reads reach EOF at once, which closes the socket
    # and would let a second stream attach as a fresh first one.
    first = Stream.new(open: true)
    second = Stream.new(open: true)
    session = Session.new(first)
    socket = build_socket(session: session, target: EventTarget.new)
    socket.rack_response
    session.deliver_stream
    sleep 0.01

    session.instance_variable_get(:@on_stream).call(second)

    assert second.closed, "a second cable stream must be closed so the client is not left waiting"
    refute first.closed
  end

  def test_close_still_closes_the_session_when_closing_the_stream_fails
    stream = Stream.new(handshake, open: true)
    stream.define_singleton_method(:close) { raise IOError, "stream already gone" }
    session = Session.new(stream)
    socket = build_socket(session: session)
    socket.rack_response
    session.deliver_stream
    wait_until { socket.alive? }

    assert_raises(IOError) { socket.close }
    refute session.open?, "a stream that fails to close must not leave its session open"
  end

  def test_transmit_writes_to_webtransport_stream
    stream = Stream.new(handshake, open: true)
    session = Session.new(stream)
    socket = build_socket(session: session)

    socket.rack_response
    session.deliver_stream
    wait_until { socket.alive? }

    assert socket.transmit("message")
    assert_equal [["message".bytesize].pack("N") + "message"], stream.writes
  end

  def test_handshake_credential_is_in_env_before_on_open
    # on_open is what runs the connection's #connect. Browsers send no cookies on a WebTransport
    # CONNECT, so the credential has to be in place by then or every connection is anonymous.
    stream = Stream.new(handshake("signed-credential"), open: true)
    session = Session.new(stream)
    env = { "quicsilver.context" => Context.new(webtransport: session) }
    credential_at_open = :not_opened
    target = EventTarget.new
    target.define_singleton_method(:on_open) { credential_at_open = env[Quicsilver::ActionCable::CREDENTIAL_ENV_KEY] }

    socket = Quicsilver::ActionCable::Socket.new(env, target)
    socket.rack_response
    session.deliver_stream
    wait_until { credential_at_open != :not_opened }

    assert_equal "signed-credential", credential_at_open
  end

  def test_handshake_credential_reaches_a_request_memoized_from_a_copy_of_env
    # Under Rails, Socket#request is built from env_config.merge(env) — a copy — and memoized by
    # the tagged logger when the CONNECT is logged, before the handshake arrives. Writing to env
    # alone passed every test here and rejected every cable in a real app.
    stream = Stream.new(handshake("signed-credential"), open: true)
    session = Session.new(stream)
    env = { "quicsilver.context" => Context.new(webtransport: session) }
    memoized = Struct.new(:env).new(env.merge("action_dispatch.copied" => true))
    credential_at_open = :not_opened
    target = EventTarget.new
    target.define_singleton_method(:request) { memoized }
    target.define_singleton_method(:on_open) { credential_at_open = Quicsilver::ActionCable.credential(memoized) }

    socket = Quicsilver::ActionCable::Socket.new(env, target)
    socket.rack_response
    session.deliver_stream
    wait_until { credential_at_open != :not_opened }

    assert_equal "signed-credential", credential_at_open
  end

  # Browsers send no cookies on a WebTransport CONNECT. The page's cookies come back in the handshake,
  # and #connect has to see them through the request's cookie jar. A log tag that reads cookies when
  # the CONNECT is logged builds that jar before the handshake arrives, so it must not stick.
  def test_handshake_cookies_reach_a_cookie_jar_built_before_the_handshake
    with_cookie_bridge do |bridge|
      seen = cookie_seen_at_open(handshake(cookies: bridge.token_for("session_token" => "signed-session")),
        build_jar_early: true)

      assert_equal "signed-session", seen
    end
  end

  # On Rails 8.0 and 8.1 the event target is the connection itself, whose #request is private.
  def test_handshake_cookies_reach_a_connection_whose_request_is_private
    with_cookie_bridge do |bridge|
      seen = cookie_seen_at_open(handshake(cookies: bridge.token_for("session_token" => "signed-session")),
        build_jar_early: true, private_request: true)

      assert_equal "signed-session", seen
    end
  end

  def test_handshake_cookies_never_replace_cookies_the_request_carried
    with_cookie_bridge do |bridge|
      seen = cookie_seen_at_open(handshake(cookies: bridge.token_for("session_token" => "from-the-page")),
        env: { "HTTP_COOKIE" => "session_token=on-the-request" })

      assert_equal "on-the-request", seen
    end
  end

  def test_a_forged_cookie_token_restores_nothing
    with_cookie_bridge do
      forged = Quicsilver::ActionCable::CookieBridge.new(secret: "o" * 32, names: %w[session_token])

      assert_nil cookie_seen_at_open(handshake(cookies: forged.token_for("session_token" => "stolen")))
    end
  end

  # An expired or foreign token signs the user out of the cable; that must be visible.
  def test_a_cookie_token_this_app_cannot_read_is_reported
    with_cookie_bridge do
      forged = Quicsilver::ActionCable::CookieBridge.new(secret: "o" * 32, names: %w[session_token])

      log = with_transport_log { cookie_seen_at_open(handshake(cookies: forged.token_for("session_token" => "x"))) }

      assert_match(/cookie token .* expired or was not issued by this app/, log)
    end
  end

  # A signed-out page renders no token. Nothing surprising, so nothing to say.
  def test_a_cable_without_a_cookie_token_logs_nothing
    with_cookie_bridge do
      assert_empty with_transport_log { cookie_seen_at_open(handshake) }
    end
  end

  def test_handshake_is_not_delivered_as_a_cable_message
    stream = Stream.new(handshake("signed-credential"), '{"command":"subscribe"}')
    session = Session.new(stream)
    target = EventTarget.new
    socket = build_socket(session: session, target: target)

    socket.rack_response
    session.deliver_stream
    wait_until { target.closed }

    assert_equal ['{"command":"subscribe"}'], target.messages
  end

  def test_a_client_without_a_handshake_still_gets_its_first_message_delivered
    # An older client opens straight into Action Cable traffic. Treating that first command as a
    # handshake would drop it, and the subscription would silently never happen.
    stream = Stream.new('{"command":"subscribe"}', "not json")
    session = Session.new(stream)
    target = EventTarget.new
    socket = build_socket(session: session, target: target)

    socket.rack_response
    session.deliver_stream
    wait_until { target.closed }

    assert target.opened
    assert_equal ['{"command":"subscribe"}', "not json"], target.messages
  end

  def test_credential_reads_nil_when_absent_or_blank
    request = Struct.new(:env).new({})
    assert_nil Quicsilver::ActionCable.credential(request)

    request.env[Quicsilver::ActionCable::CREDENTIAL_ENV_KEY] = ""
    assert_nil Quicsilver::ActionCable.credential(request)
  end

  private

  def handshake(credential = nil, cookies: nil)
    JSON.generate(quicsilver_handshake: { cookies: cookies, credential: credential })
  end

  def with_transport_log
    previous = Quicsilver.logger
    output = StringIO.new
    Quicsilver.logger = Logger.new(output, level: Logger::INFO)
    yield
    output.string
  ensure
    Quicsilver.logger = previous
  end

  def with_cookie_bridge
    previous = Quicsilver::ActionCable.cookie_bridge
    bridge = Quicsilver::ActionCable::CookieBridge.new(secret: "s" * 32, names: %w[session_token])
    Quicsilver::ActionCable.cookie_bridge = bridge
    yield bridge
  ensure
    Quicsilver::ActionCable.cookie_bridge = previous
  end

  # The session_token cookie #connect would read, given a handshake frame. Mirrors Rails: the
  # request #connect uses is a copy of env, memoized when the CONNECT is logged.
  def cookie_seen_at_open(frame, env: {}, build_jar_early: false, private_request: false)
    session = Session.new(Stream.new(frame, open: true))
    env = env.merge("quicsilver.context" => Context.new(webtransport: session))
    request = ActionDispatch::Request.new(env.dup)
    request.cookie_jar if build_jar_early
    seen = :not_opened
    target = EventTarget.new
    target.define_singleton_method(:request) { request }
    target.singleton_class.send(:private, :request) if private_request
    target.define_singleton_method(:on_open) { seen = request.cookie_jar["session_token"] }

    Quicsilver::ActionCable::Socket.new(env, target).rack_response
    session.deliver_stream
    wait_until { seen != :not_opened }
    seen
  end

  def build_socket(session: Session.new(Stream.new), target: EventTarget.new)
    env = { "quicsilver.context" => Context.new(webtransport: session) }
    Quicsilver::ActionCable::Socket.new(env, target)
  end
end
