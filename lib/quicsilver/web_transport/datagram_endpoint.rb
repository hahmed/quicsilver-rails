# frozen_string_literal: true

require "quicsilver/web_transport/endpoint"
require "quicsilver/web_transport/codec"
require "quicsilver/web_transport/message_codec"

module Quicsilver
  module WebTransport
    # Endpoint for unreliable, unordered WebTransport datagrams.
    #
    # Example:
    #   class CursorTransport < Quicsilver::WebTransport::DatagramEndpoint
    #     receives CursorUpdate
    #
    #     def receive(cursor)
    #       broadcast_cursor cursor
    #     end
    #   end
    class DatagramEndpoint < Endpoint
      include MessageCodec

      setting :receives
      setting :codec, default: :raw

      def receive(_message)
        raise NotImplementedError, "#{self.class} must implement #receive"
      end

      private

      def run
        session.on_datagram do |packet|
          receive decode_with(self.class.receives, packet)
        end

        wait_for_session_close
      end
    end
  end
end
