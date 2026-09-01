# frozen_string_literal: true

require "quicsilver/web_transport/endpoint"
require "quicsilver/web_transport/codec"

module Quicsilver
  module WebTransport
    class Channel < Endpoint
      class << self
        def command(type, to:)
          commands[type.to_s] = to
        end

        def stream(type, to:)
          streams[type.to_s] = to
        end

        def commands
          @commands ||= superclass.respond_to?(:commands) ? superclass.commands.dup : {}
        end

        def streams
          @streams ||= superclass.respond_to?(:streams) ? superclass.streams.dup : {}
        end
      end

      def handle_stream(raw_stream)
        dispatcher.call(raw_stream)
      end

      private
        def run
          each_stream { |raw_stream| handle_stream(raw_stream) }
          wait_for_session_close
        end

        def dispatcher
          @dispatcher ||= Dispatcher.new(
            commands: self.class.commands,
            streams: self.class.streams,
            codec: codec,
            session: session
          )
        end

        def codec
          @codec ||= Codec.resolve(:json)
        end
    end
  end
end

require "quicsilver/web_transport/channel/dispatcher"
