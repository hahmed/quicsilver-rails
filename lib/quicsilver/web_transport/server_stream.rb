# frozen_string_literal: true

require "quicsilver/web_transport/endpoint"
require "quicsilver/web_transport/codec"
require "quicsilver/web_transport/message_codec"
require "quicsilver/action_cable/framed_stream"

module Quicsilver
  module WebTransport
    # One request message in, many response messages out over a reliable
    # WebTransport bidirectional stream.
    #
    # Example:
    #   class CompletionStream < Quicsilver::WebTransport::ServerStream
    #     receives CompletionRequest
    #     streams Token
    #
    #     def perform(request)
    #       Ai.tokens(request.prompt)
    #     end
    #   end
    class ServerStream < Endpoint
      include MessageCodec

      class << self
        def receives(type = nil)
          @receives = type if type
          @receives
        end

        def streams(type = nil)
          @streams = type if type
          @streams
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
        session.each_stream do |raw_stream|
          handle_stream(raw_stream)
        end
      end

      def handle_stream(raw_stream)
        stream = Quicsilver::ActionCable::FramedStream.new(raw_stream)
        payload = stream.read_message
        return unless payload

        request = decode_with(self.class.receives, payload)
        responses = perform(request)
        responses = [responses] unless responses.respond_to?(:each) && !responses.is_a?(String)

        responses.each do |response|
          stream.write_message encode_with(self.class.streams, response)
        end
      ensure
        stream&.close
      end
    end
  end
end
