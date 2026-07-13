# frozen_string_literal: true

require "quicsilver/web_transport/endpoint"
require "quicsilver/web_transport/codec"
require "quicsilver/web_transport/message_codec"
require "quicsilver/web_transport/framed_stream"

module Quicsilver
  module WebTransport
    # One request message in, one response message out over a reliable
    # WebTransport bidirectional stream.
    #
    # Example:
    #   class ApplyOperation < Quicsilver::WebTransport::RpcEndpoint
    #     codec :json
    #
    #     def perform(operation)
    #       document.apply(operation)
    #     end
    #   end
    class RpcEndpoint < Endpoint
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

      def perform(_request)
        raise NotImplementedError, "#{self.class} must implement #perform"
      end

      private

      def run
        session.on_stream do |raw_stream|
          spawn { handle_stream(raw_stream) }
        end

        wait_for_session_close
      end

      def handle_stream(raw_stream)
        stream = Quicsilver::WebTransport::FramedStream.new(raw_stream)
        payload = stream.read_message
        return unless payload

        request = decode_with(self.class.receives, payload)
        response = perform(request)
        stream.write_message encode_with(self.class.returns, response) unless response.nil?
      ensure
        stream&.close
      end
    end
  end
end
