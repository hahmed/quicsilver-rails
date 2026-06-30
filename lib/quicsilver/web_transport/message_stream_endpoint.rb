# frozen_string_literal: true

require "quicsilver/web_transport/endpoint"
require "quicsilver/web_transport/codec"
require "quicsilver/web_transport/message_codec"
require "quicsilver/web_transport/framed_stream"

module Quicsilver
  module WebTransport
    # Many request messages in, optional response messages out over a reliable
    # WebTransport bidirectional stream.
    #
    # Example:
    #   class ChatStream < Quicsilver::WebTransport::MessageStreamEndpoint
    #     codec :json
    #
    #     def receive(message)
    #       Chat.broadcast(message)
    #     end
    #   end
    #
    # If #receive returns nil, no response message is written. Any non-nil
    # return value is encoded and written as one response message.
    class MessageStreamEndpoint < Endpoint
      include MessageCodec

      class << self
        def receives(type = nil)
          @receives = type if type
          @receives
        end

        def returns(type = nil)
          @returns = type if type
          @returns
        end

        def codec(value = nil)
          @codec = value if value
          @codec || :raw
        end
      end

      def receive(_message)
        raise NotImplementedError, "#{self.class} must implement #receive"
      end

      private

      def run
        session.each_stream do |raw_stream|
          handle_stream(raw_stream)
        end
      end

      def handle_stream(raw_stream)
        stream = Quicsilver::WebTransport::FramedStream.new(raw_stream)

        while (payload = stream.read_message)
          message = decode_with(self.class.receives, payload)
          response = receive(message)
          stream.write_message encode_with(self.class.returns, response) unless response.nil?
        end
      ensure
        stream&.close
      end
    end
  end
end
