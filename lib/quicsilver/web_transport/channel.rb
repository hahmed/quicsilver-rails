# frozen_string_literal: true

require "quicsilver/web_transport/endpoint"
require "quicsilver/web_transport/codec"
require "quicsilver/web_transport/message_codec"

module Quicsilver
  module WebTransport
    class Channel < Endpoint
      include MessageCodec

      class << self
        def command(type, to:)
          commands[type.to_s] = to
        end

        # Wire format for commands, streams and datagrams.
        #
        #   class DropChannel < Quicsilver::WebTransport::Channel
        #     codec :json
        #   end
        #
        # Defaults to :json rather than :raw because channels exchange typed
        # messages: the dispatcher routes on message["type"], which needs a
        # structured payload. Subclasses inherit the parent's choice.
        def codec(value = nil)
          @codec = value if value
          @codec || inherited_codec
        end

        def stream(type, to:)
          streams[type.to_s] = to
        end

        def datagram(&block)
          @datagram_handler = block if block
          @datagram_handler
        end

        def commands
          @commands ||= superclass.respond_to?(:commands) ? superclass.commands.dup : {}
        end

        def streams
          @streams ||= superclass.respond_to?(:streams) ? superclass.streams.dup : {}
        end

        private
          def inherited_codec
            superclass.respond_to?(:codec) ? superclass.codec : :json
          end
      end

      def handle_stream(raw_stream)
        dispatcher.call(raw_stream)
      end

      private
        def run
          each_stream { |raw_stream| handle_stream(raw_stream) }
          each_datagram { |packet| handle_datagram(packet) } if self.class.datagram
          wait_for_session_close
        end

        def handle_datagram(packet)
          instance_exec(packet, &self.class.datagram)
        end

        def dispatcher
          @dispatcher ||= Dispatcher.new(
            commands: self.class.commands,
            streams: self.class.streams,
            codec: codec,
            session: session
          )
        end
    end
  end
end

require "quicsilver/web_transport/channel/dispatcher"
