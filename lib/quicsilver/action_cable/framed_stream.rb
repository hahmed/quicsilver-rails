# frozen_string_literal: true

module Quicsilver
  module ActionCable
    # Length-prefixed message framing for carrying Action Cable messages over a
    # reliable WebTransport byte stream.
    #
    # WebSocket gives Action Cable message boundaries for free. WebTransport
    # streams are byte streams, so this wrapper turns arbitrary stream chunks
    # into complete messages and frames outbound messages the same way.
    class FramedStream
      MAX_MESSAGE_SIZE = 16 * 1024 * 1024

      def initialize(stream, max_message_size: MAX_MESSAGE_SIZE)
        @stream = stream
        @max_message_size = max_message_size
        @buffer = "".b
      end

      def read_message
        loop do
          if (message = take_message)
            return message
          end

          chunk = @stream.read
          return nil unless chunk

          @buffer << chunk.b
        end
      end

      def write_message(message)
        payload = message.to_s.b
        @stream.write([payload.bytesize].pack("N") + payload)
      end

      def close
        @stream.close
      end

      private

      def take_message
        return nil if @buffer.bytesize < 4

        length = @buffer.byteslice(0, 4).unpack1("N")
        raise Error, "Action Cable WebTransport message too large" if length > @max_message_size
        return nil if @buffer.bytesize < 4 + length

        message = @buffer.byteslice(4, length)
        @buffer = @buffer.byteslice(4 + length..-1) || "".b
        message
      end
    end
  end
end
