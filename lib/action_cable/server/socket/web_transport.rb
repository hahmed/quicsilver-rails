# frozen_string_literal: true

require "action_cable/server/socket"
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
      class WebTransport # :nodoc:
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
          return if @open

          @raw_stream = raw_stream
          @stream = Quicsilver::WebTransport::FramedStream.new(@raw_stream)
          @open = true
          @event_target.on_open
          start_reader
        end

        def start_reader
          @reader = Thread.new do
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
      end
    end
  end
end
