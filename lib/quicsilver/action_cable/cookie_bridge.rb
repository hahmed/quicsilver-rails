# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/integer/time"
require "active_support/message_encryptor"
require "rack/utils"

module Quicsilver
  module ActionCable
    # Gives a WebTransport cable the cookies the browser leaves out.
    #
    # Browsers send no cookies on a WebTransport CONNECT, so an app's usual lookup in
    # ApplicationCable::Connection#connect finds nobody. The page that opens the cable did arrive
    # with cookies, though. The bridge encrypts the allowlisted ones into a token the page renders,
    # the socket sends it back in its handshake frame, and the adapter restores them as the
    # request's Cookie header before #connect runs. The app authenticates the cable exactly as it
    # does over a WebSocket.
    #
    # Only the cookies named in config.quicsilver.cable_cookies travel, so unrelated cookies stay
    # out of the page. Without it, the ones Rails apps sign in with by default (see .default_names).
    # The token is encrypted, expires, and is only read on a cable handshake.
    #
    # It carries a snapshot: a cookie rotated after the page rendered arrives stale until the next
    # page load. Revoking access on logout depends on the app's lookup: a database-backed session
    # stops working when its row goes, but a cookie-store session keeps working until the token
    # expires, as a copied cookie would.
    class CookieBridge
      PURPOSE = "quicsilver.action_cable.cookies"
      EXPIRES_IN = 1.day

      def self.from_rails
        app = ::Rails.application if defined?(::Rails)
        return unless app

        names = app.config.quicsilver.cable_cookies || default_names(app)
        new(secret: app.key_generator.generate_key(PURPOSE, 32), names: names)
      end

      # The session cookie, which holds a Devise or session[:user_id] sign-in, and session_id, the
      # cookie Rails' authentication generator signs users in with. Only those present travel.
      def self.default_names(app)
        [ app.config.session_options.to_h[:key], "session_id" ].compact
      end

      def initialize(secret:, names:)
        @encryptor = ActiveSupport::MessageEncryptor.new(secret)
        @names = Array(names).map(&:to_s)
      end

      # The token for a request's cookies, or nil when none of the allowlisted ones are present.
      def token_for(cookies)
        selected = cookies.to_h.slice(*@names)
        @encryptor.encrypt_and_sign(cookie_header(selected), purpose: PURPOSE, expires_in: EXPIRES_IN) if selected.any?
      end

      # The Cookie header a token carries, or nil when it is missing, forged or expired.
      def read(token)
        @encryptor.decrypt_and_verify(token, purpose: PURPOSE) if token.is_a?(String) && !token.empty?
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        nil
      end

      private
        # Escaped the way Rack escapes a value it sets, so Rack parses back exactly what the browser sent.
        def cookie_header(cookies)
          cookies.map { |name, value| "#{::Rack::Utils.escape(name)}=#{::Rack::Utils.escape(value)}" }.join("; ")
        end
    end
  end
end
