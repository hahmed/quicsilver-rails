# frozen_string_literal: true

require "json"
require "quicsilver/web_transport"
require "quicsilver/web_transport/framed_stream"

module Quicsilver
  module ActionCable
    # Action Cable socket adapter backed by a Quicsilver WebTransport session.
    #
    # This implements the same small transport surface as Action Cable's own WebSocket wrapper
    # (ActionCable::Connection::WebSocket on Rails 8.0 and 8.1, ActionCable::Server::Socket::WebSocket
    # on later Rails):
    #
    # - possible?
    # - alive?
    # - transmit
    # - close
    # - protocol
    # - rack_response
    #
    # It intentionally uses one reliable WebTransport bidirectional stream.
    # Action Cable keeps its own channel multiplexing and JSON protocol.
    #
    # Browsers send no cookies on a WebTransport CONNECT, so cookie-based
    # Action Cable authentication sees an anonymous request and rejects it.
    # The client therefore opens the stream with one handshake frame carrying
    # a credential the page rendered, and the connection's #connect reads it
    # through Quicsilver::ActionCable.credential. It travels in the stream,
    # not the URL, so it stays out of request logs.
    class Socket
      HANDSHAKE_KEY = "quicsilver_handshake"

      attr_reader :session, :stream

      def initialize(env, event_target, event_loop = nil, protocols: self.class.default_protocols)
        @env = env
        @event_target = event_target
        @event_loop = event_loop
        @protocols = protocols
        @session = Quicsilver::WebTransport.from_env(env)
        @raw_stream = nil
        @stream = nil
        @reader = nil
        @open = false
      end

      def possible?
        !!session
      end

      def alive?
        @open && session&.open?
      end

      def transmit(message)
        return false unless alive? && stream

        stream.write_message(message)
        true
      end

      def close(_code = nil, _reason = nil)
        @open = false
        stream&.close
      ensure
        session&.close
      end

      def protocol
        @protocols.first
      end

      def rack_response
        return [404, {}, []] unless possible?

        session.accept!
        session.on_stream { |raw_stream| attach_stream(raw_stream) }

        [200, {}, []]
      rescue => error
        @event_target.on_error(error.message) if @event_target.respond_to?(:on_error)
        close
        [500, {}, []]
      end

      def self.default_protocols
        if ::ActionCable.const_defined?(:INTERNAL)
          ::ActionCable::INTERNAL[:protocols]
        else
          ["actioncable-v1-json"]
        end
      end

      private

      attr_reader :event_target

      def attach_stream(raw_stream)
        # One stream carries the cable protocol. A client that opens another
        # is told so rather than left waiting on a stream nothing reads.
        # Checked against the stream rather than @open, which only flips once
        # the handshake has been read on the reader thread.
        if @stream
          raw_stream.close
          return
        end

        @raw_stream = raw_stream
        @stream = Quicsilver::WebTransport::FramedStream.new(@raw_stream)
        start_reader
      end

      def start_reader
        @reader = Thread.new do
          # The handshake is read before on_open, because on_open is what
          # runs the connection's #connect — authentication has to find the
          # credential already in place. It also means nothing is transmitted
          # until the client has a stream to receive it on.
          pending = read_handshake

          @open = true
          event_target.on_open
          event_target.on_message(pending) if pending

          while alive? && (message = stream.read_message)
            event_target.on_message(message)
          end
        rescue => error
          unless session_ended?(error)
            event_target.on_error(error.message) if event_target.respond_to?(:on_error)
          end
        ensure
          @open = false
          event_target.on_close("", 1000)
        end
      end

      # WT_SESSION_GONE is how a stream learns its session closed: the spec resets every stream of
      # a session that ends, including when the server closes it on shutdown. That is the cable
      # closing, not failing, so it reaches #on_close without an error.
      def session_ended?(error)
        defined?(Quicsilver::Server::WebTransportStream::ResetError) &&
          error.is_a?(Quicsilver::Server::WebTransportStream::ResetError) &&
          error.http_error_code == Quicsilver::Protocol::WebTransport::SESSION_GONE
      end

      # Reads the client's first frame. The handshake is required: the server
      # waits for it before running #connect, so a client that waits for
      # `welcome` first will never get one. A first frame that is not a
      # handshake is still delivered as a cable message rather than eaten.
      def read_handshake
        first = stream.read_message
        return nil unless first

        payload = JSON.parse(first)

        if payload.is_a?(Hash) && payload.key?(HANDSHAKE_KEY)
          handshake = payload[HANDSHAKE_KEY]
          store_cookies(handshake["cookies"])
          store_credential(handshake["credential"])
          nil
        else
          first
        end
      rescue JSON::ParserError
        first
      end

      # Written to the request the connection reads, not only to env. Under
      # Rails, Socket#request is Rails.application.env_config.merge(env) — a
      # copy — and the tagged logger memoizes it when "Started CONNECT" is
      # logged, long before the handshake arrives. A credential written to
      # env alone is invisible to #connect, and every cable is rejected.
      def store_credential(credential)
        request_envs.each { |env| env[Quicsilver::ActionCable::CREDENTIAL_ENV_KEY] = credential }
      end

      # Restores the cookies the page sent, which WebTransport left off the CONNECT, so the app's
      # own cookie lookup in #connect finds the session. Written where the credential goes, for the
      # same reason, and the memoized cookie jar is dropped too: anything that read cookies before
      # the handshake arrived, such as a log tag, built an empty jar that would otherwise stick.
      #
      # Never replaces cookies the request really carried.
      def store_cookies(token)
        # A signed-out page renders no token: an ordinary anonymous cable.
        return if token.blank?

        header = Quicsilver::ActionCable.cookie_bridge&.read(token)
        unless header
          Quicsilver.logger.warn "A WebTransport cable sent a cookie token that has expired or was not issued by " \
            "this app, so it connects without cookies. A page reload issues a new one."
          return
        end

        Quicsilver.logger.debug { "WebTransport cable restored cookies: #{header.split("; ").map { _1.split("=", 2).first }.join(", ")}" }
        request_envs.each do |env|
          next if env["HTTP_COOKIE"].present?

          env["HTTP_COOKIE"] = header
          env.delete("action_dispatch.cookies")
        end
      end

      def request_envs
        envs = [ @env ]
        # Private on Rails 8.0 and 8.1, where the event target is the connection itself.
        envs << event_target.send(:request).env if event_target.respond_to?(:request, true)
        envs.uniq(&:object_id)
      end
    end
  end
end
