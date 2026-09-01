# frozen_string_literal: true

require "quicsilver/web_transport/framed_stream"

module Quicsilver
  module WebTransport
    class Channel
      class Dispatcher
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
        rescue => exception
          stream&.write_message encode(error(exception.message))
          stream&.close
        end

        private
          attr_reader :commands, :streams, :codec, :session

          def decode(payload)
            return unless payload

            codec.decode(payload)
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
