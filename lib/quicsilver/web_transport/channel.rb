# frozen_string_literal: true

require "quicsilver/web_transport/endpoint"
require "quicsilver/web_transport/codec"
require "quicsilver/web_transport/message_codec"

module Quicsilver
  module WebTransport
    class Channel < Endpoint
      include MessageCodec

      # Wire format for commands, streams and datagrams.
      #
      #   class DropChannel < Quicsilver::WebTransport::Channel
      #     codec :json
      #   end
      #
      # Defaults to :json rather than :raw because channels exchange typed
      # messages: the dispatcher routes on message["type"], which needs a
      # structured payload. Subclasses inherit the parent's choice.
      setting :codec, default: :json

      # Inherited like any setting. Adding to a subclass replaces its copy rather than editing the
      # parent's, and a subclass that adds nothing keeps reading the parent's.
      class_attribute :commands, :streams, instance_accessor: false, default: {}.freeze
      class_attribute :_datagram_handler, instance_accessor: false

      class << self
        def command(type, to:)
          self.commands = commands.merge(type.to_s => to).freeze
        end

        def stream(type, to:)
          self.streams = streams.merge(type.to_s => to).freeze
        end

        def datagram(&block)
          block ? self._datagram_handler = block : _datagram_handler
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
