# frozen_string_literal: true

module Quicsilver
  module Middleware
    # Injects Alt-Svc so browsers can discover the HTTP/3 endpoint served by
    # Quicsilver over UDP.
    class AltSvc
      def initialize(app, port: 4433, max_age: 86_400)
        @app = app
        @alt_svc_value = %(h3=":#{port}"; ma=#{max_age})
      end

      def call(env)
        status, headers, body = @app.call(env)
        headers["alt-svc"] = @alt_svc_value
        [status, headers, body]
      end
    end
  end
end
