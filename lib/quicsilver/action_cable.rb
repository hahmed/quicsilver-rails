# frozen_string_literal: true

require "action_cable/server/socket"
require "quicsilver/action_cable/framed_stream"
require "action_cable/server/socket/web_transport"

module Quicsilver
  module ActionCable
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
