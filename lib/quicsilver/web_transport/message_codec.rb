# frozen_string_literal: true

module Quicsilver
  module WebTransport
    module MessageCodec
      private

      def decode_with(type, payload)
        return codec.decode(payload) unless type
        return type.decode(payload) if type.respond_to?(:decode)
        return type.load(payload) if type.respond_to?(:load)

        type.new(codec.decode(payload))
      end

      def encode_with(type, value)
        return codec.encode(value) unless type
        return type.encode(value) if type.respond_to?(:encode)
        return type.dump(value) if type.respond_to?(:dump)

        codec.encode(value)
      end

      def codec
        @codec ||= Codec.resolve(self.class.codec)
      end
    end
  end
end
