# frozen_string_literal: true

require "logger"

module Quicsilver
  module Rails
    # Quicsilver's transport log (handshakes, WebTransport sessions, stream resets), written through
    # Rails.logger so it lands in log/<env>.log beside the requests it explains, in the app's format.
    #
    # Keeps its own level: QUICSILVER_DEBUG turns on transport detail without turning the whole
    # app's log to DEBUG, and Rails.logger's level still applies on top.
    class TransportLogger < ::Logger
      TAG = "[quicsilver]"

      def initialize(target, level: ::Logger::INFO)
        super(nil, level: level)
        @target = target
      end

      def add(severity, message = nil, progname = nil)
        severity ||= UNKNOWN
        return true if severity < level

        message = block_given? ? yield : (message || progname)
        @target.add(severity, "#{TAG} #{message}")
      end
      alias_method :log, :add
    end
  end
end
