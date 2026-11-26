# frozen_string_literal: true

require_relative "../rails/port"

module Quicsilver
  module Middleware
    # Injects Alt-Svc so browsers can discover the HTTP/3 endpoint served by
    # Quicsilver over UDP. Advertises the port the listener binds unless told otherwise.
    class AltSvc
      # The middleware's options for a config.quicsilver.alt_svc setting, or nil to leave it out.
      # Unset, it is on whenever QUICSILVER_PORT names an HTTP/3 listener, so starting one is all it
      # takes for browsers to find it. false turns it off; true or a hash of options turns it on.
      def self.options_for(setting, env: ENV)
        setting = !env["QUICSILVER_PORT"].to_s.empty? if setting.nil?
        return unless setting

        setting == true ? {} : setting
      end

      def initialize(app, port: Quicsilver::Rails.port, max_age: 86_400)
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
