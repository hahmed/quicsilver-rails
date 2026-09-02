# frozen_string_literal: true

module Quicsilver
  module WebTransport
    # Base class for long-lived channel streams.
    #
    #   class Activity < Quicsilver::WebTransport::StreamHandler
    #     def call
    #       write Payload.snapshot(product)
    #       loop { write queue.pop }
    #     ensure
    #       close
    #     end
    #   end
    #
    #   class DropChannel < Quicsilver::WebTransport::Channel
    #     stream "subscribe", to: Activity
    #   end
    #
    # A command handles one message and replies. A stream handler owns the
    # stream for its lifetime: it decides what to write, when, and when to
    # finish. The dispatcher does not close the stream afterwards, so a handler
    # that returns without closing leaves the peer waiting.
    #
    # The dispatcher passes context as keyword arguments. #initialize absorbs
    # unknown keys so adding one later cannot break existing handlers — plain
    # classes implementing `self.call` have to write `**` by hand to survive
    # the same change.
    class StreamHandler
      def self.call(**context)
        new(**context).call
      end

      def initialize(stream:, codec:, session: nil, message: nil, **context)
        @stream = stream
        @codec = codec
        @session = session
        @message = message
        @context = context
      end

      attr_reader :stream, :codec, :session, :message, :context

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      private
        # Encode and send one message.
        def write(payload)
          stream.write_message(codec.encode(payload))
        end

        # Read and decode the next message, or nil once the peer is done.
        def read
          payload = stream.read_message
          codec.decode(payload) if payload
        end

        def close
          stream.close
        end
    end
  end
end
