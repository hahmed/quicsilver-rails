# frozen_string_literal: true

begin
  require "action_cable/connection/client_socket"
rescue LoadError
  require "action_cable/server/socket"
end

require "quicsilver/web_transport/framed_stream"
require "action_cable/server/socket/web_transport"

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

    module SocketSelection
      def initialize(server, env, coder: ActiveSupport::JSON)
        super

        return unless Quicsilver::WebTransport.from_env(env)

        @websocket = ::ActionCable::Server::Socket::WebTransport.new(env, self, event_loop)
      end
    end

    module_function

    def install!
      return if @installed

      ::ActionCable::Server::Socket.prepend(SocketSelection)
      ::ActionCable::Connection::Base.include(Connection)
      @installed = true
    end
  end
end
