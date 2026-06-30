# frozen_string_literal: true

require "json"

module Quicsilver
  module WebTransport
    module Codec
      module Raw
        module_function

        def decode(payload)
          payload
        end

        def encode(value)
          value.to_s
        end
      end

      module JSON
        module_function

        def decode(payload)
          ::JSON.parse(payload)
        end

        def encode(value)
          ::JSON.generate(value)
        end
      end

      module_function

      def resolve(codec)
        case codec
        when nil, :raw then Raw
        when :json then JSON
        else codec
        end
      end
    end
  end
end
