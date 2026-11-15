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
    #       Session.find_signed(Quicsilver::ActionCable.credential(request), purpose: :cable)
    #   end
    def self.credential(request)
      request.env[CREDENTIAL_ENV_KEY].presence
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
      @installed = true
    end
  end
end
