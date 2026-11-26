# frozen_string_literal: true

require "quicsilver/web_transport/framed_stream"

module Quicsilver
  module WebTransport
    class Channel
      class Dispatcher
        # The payload could not be decoded: the peer's mistake, not the app's, so it is answered but
        # not reported.
        class MalformedMessage < StandardError; end

        def initialize(commands:, streams:, codec:, session:)
          @commands = commands
          @streams = streams
          @codec = codec
          @session = session
        end

        def call(raw_stream)
          stream = FramedStream.new(raw_stream)
          message = decode(stream.read_message)
          return stream.close unless message

          if (handler = commands[message["type"].to_s])
            stream.write_message encode(handler.call(message))
            stream.close
          elsif (handler = streams[message["type"].to_s])
            handler.call(stream: stream, codec: codec, session: session, message: message)
          else
            stream.write_message encode(error("Unknown WebTransport message type: #{message['type']}"))
            stream.close
          end
        rescue Quicsilver::Server::WebTransportStream::ResetError
          # The peer reset the stream: an ordinary disconnect, and nobody is left to reply to.
          nil
        rescue MalformedMessage
          reply_with_error(stream, "Malformed message")
        rescue => exception
          # The peer gets a generic reply: the exception's message can carry SQL, record data or
          # paths. The app's error reporter gets the exception itself.
          ::Rails.error.report(exception, handled: true, source: "quicsilver.webtransport")
          reply_with_error(stream, "Internal error")
        end

        private
          attr_reader :commands, :streams, :codec, :session

          def decode(payload)
            return unless payload

            codec.decode(payload)
          rescue => error
            raise MalformedMessage, error.message
          end

          # Best effort. The stream may already be gone, and a failure here must not replace the
          # error being answered.
          def reply_with_error(stream, message)
            stream&.write_message encode(error(message))
            stream&.close
          rescue IOError, Quicsilver::Server::WebTransportStream::ResetError
            nil
          end

          def encode(payload)
            codec.encode(payload)
          end

          def error(message)
            { type: "error", error: message }
          end
      end
    end
  end
end
