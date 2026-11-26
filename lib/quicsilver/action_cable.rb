# frozen_string_literal: true

# Loads ActionCable::Server::Socket on Rails versions that have it; see .socket_owner.
begin
  require "action_cable/server/socket"
rescue LoadError
end

require "quicsilver/action_cable/cookie_bridge"

module Quicsilver
  module ActionCable
    # Where the WebTransport socket puts the credential from the client's
    # handshake frame. Read it through .credential rather than by key.
    CREDENTIAL_ENV_KEY = "quicsilver.cable.credential"

    # The credential the client sent when it opened a WebTransport cable, or
    # nil over a TCP WebSocket. Call from ApplicationCable::Connection#connect,
    # alongside whatever cookie lookup the app already does:
    #
    #   def find_session
    #     Session.find_signed(cookies.signed[:session_token]) ||
    #       Session.find_signed(quicsilver_cable_credential, purpose: :cable)
    #   end
    def self.credential(request)
      request.env[CREDENTIAL_ENV_KEY].presence
    end

    # Included into ActionCable::Connection::Base, so a connection can write
    #
    #   Session.find_signed(quicsilver_cable_credential, purpose: :cable)
    module Connection
      private
        def quicsilver_cable_credential
          Quicsilver::ActionCable.credential(request)
        end
    end

    # Swaps Action Cable's WebSocket wrapper for the WebTransport socket when the request is a
    # WebTransport session. Every other request keeps its WebSocket.
    module SocketSelection
      def initialize(server, env, coder: ActiveSupport::JSON)
        super

        return unless Quicsilver::WebTransport.from_env(env)

        @websocket = Quicsilver::ActionCable::Socket.new(env, self, event_loop)
      end
    end

    module_function

    # The class that builds a request's socket, in #initialize(server, env, coder:), as
    # `@websocket = WebSocket.new(env, self, event_loop)`. Rails 8.0 and 8.1 do it in the connection;
    # later Rails moved it into ActionCable::Server::Socket. Asked of Rails rather than inferred from
    # its version number, so a release that moves it again fails loudly in the tests.
    def socket_owner
      defined?(::ActionCable::Server::Socket) ? ::ActionCable::Server::Socket : ::ActionCable::Connection::Base
    end

    # Shared by the page helper, which issues the token, and the socket, which reads it. Built from
    # the Rails app on first use; nil outside one, where there is no secret to encrypt with.
    def cookie_bridge
      @cookie_bridge ||= CookieBridge.from_rails
    end

    def cookie_bridge=(bridge)
      @cookie_bridge = bridge
    end

    def install!
      return if @installed

      ::ActionCable::Connection::Base.include(Connection)
      socket_owner.prepend(SocketSelection)
      @installed = true
    end
  end
end

require "quicsilver/action_cable/socket"
