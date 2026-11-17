# frozen_string_literal: true

# The adapter plugs into ActionCable::Server::Socket, which only Rails main (8.2.0.alpha) has.
# Rails 8.1 and earlier build connections on ActionCable::Connection::WebSocket instead, so there is
# nothing to plug into. The socket file is only loaded where the seam exists: loading it elsewhere
# would define an empty ActionCable::Server::Socket that nothing uses.
begin
  require "action_cable/server/socket"
rescue LoadError
end

require "quicsilver/web_transport/framed_stream"

module Quicsilver
  module ActionCable
    SEAM_AVAILABLE = defined?(::ActionCable::Server::Socket) ? true : false
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

    # Whether this Rails can carry Action Cable over WebTransport. The page helpers check it, so
    # an app on Rails 8.1 never moves its cable onto a transport the server can't accept.
    def available?
      SEAM_AVAILABLE
    end

    # Installs the adapter, or warns once and does nothing where Rails has no socket seam. Either
    # way connections get #quicsilver_cable_credential, which is nil without the adapter.
    def install!(logger: (::Rails.logger if defined?(::Rails)) || Quicsilver.logger)
      return if @installed

      ::ActionCable::Connection::Base.include(Connection)

      if available?
        ::ActionCable::Server::Socket.prepend(SocketSelection)
      else
        logger&.warn "quicsilver-rails: Action Cable over WebTransport needs Rails main (8.2.0.alpha); " \
          "Action Cable #{::ActionCable.version} has no ActionCable::Server::Socket, so cables stay on WebSocket."
      end

      @installed = true
    end
  end
end

require "action_cable/server/socket/web_transport" if Quicsilver::ActionCable.available?
