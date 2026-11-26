# frozen_string_literal: true

require "console"
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

      # An output for the console gem, which protocol-rack logs through instead of Quicsilver.logger.
      # Its error line when a Rack app raises would otherwise go to stderr, in another format and
      # missing from log/<env>.log. Forwarded into a logger, it gets the same tag and level.
      class ConsoleOutput
        SEVERITIES = {
          debug: ::Logger::DEBUG, info: ::Logger::INFO, warn: ::Logger::WARN,
          error: ::Logger::ERROR, fatal: ::Logger::FATAL
        }.freeze

        def initialize(logger)
          @logger = logger
        end

        # Console passes the exception, when there is one, as the last argument.
        def call(subject = nil, *arguments, severity: :info, **, &block)
          @logger.add(SEVERITIES.fetch(severity, ::Logger::UNKNOWN)) { format(subject, arguments, block) }
        end

        private
          def format(subject, arguments, block)
            arguments += [ block.call ] if block
            exception = arguments.pop if arguments.last.is_a?(Exception)
            text = [ label(subject), *arguments ].compact.join(" ")
            exception ? "#{text} #{exception.class}: #{exception.message}\n#{Array(exception.backtrace).join("\n")}" : text
          end

          def label(subject)
            subject.is_a?(Module) ? subject.name : subject&.class&.name
          end
      end
    end
  end
end
