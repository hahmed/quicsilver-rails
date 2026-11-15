# frozen_string_literal: true

begin
  require "action_cable/connection/client_socket"
rescue LoadError
  require "action_cable/server/socket"
end

require "json"
require "quicsilver/web_transport"
require "quicsilver/web_transport/framed_stream"

module ActionCable
  module Server
    class Socket
      # Action Cable socket adapter backed by a Quicsilver WebTransport session.
      #
      # This implements the same small transport surface as
      # ActionCable::Server::Socket::WebSocket:
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
      class WebTransport # :nodoc:
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

        private

        attr_reader :event_target

        def self.default_protocols
          if ActionCable.const_defined?(:INTERNAL)
            ActionCable::INTERNAL[:protocols]
          else
            ["actioncable-v1-json"]
          end
        end

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
            event_target.on_error(error.message) if event_target.respond_to?(:on_error)
          ensure
            @open = false
            event_target.on_close("", 1000)
          end
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
            @env[Quicsilver::ActionCable::CREDENTIAL_ENV_KEY] = payload[HANDSHAKE_KEY]["credential"]
            nil
          else
            first
          end
        rescue JSON::ParserError
          first
        end
      end
    end
  end
end
