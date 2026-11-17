# frozen_string_literal: true

require "quicsilver"
require "quicsilver/rails/dev_web_transport_certificate"
require "quicsilver/rails/transport_logger"

module Quicsilver
  module Rails
    # Boots a Quicsilver HTTP/3 listener for a Rails app, beside the app's TCP server.
    #
    #   #!/usr/bin/env ruby
    #   require_relative "../config/environment"
    #   Quicsilver::Rails::Server.start
    #
    # Port and address come from QUICSILVER_PORT / QUICSILVER_HOST. In development the
    # certificate is the same mkcert one Puma serves on TCP, since a browser switching via
    # Alt-Svc validates the UDP listener against the origin it already trusts.
    module Server
      DEFAULT_PORT = 3443

      module_function

      def start(app: ::Rails.application, port: ENV.fetch("QUICSILVER_PORT", DEFAULT_PORT),
                address: ENV.fetch("QUICSILVER_HOST", "0.0.0.0"), certificate: DevWebTransportCertificate.fetch,
                shutdown_timeout: shutdown_timeout_from_env, **transport_options)
        log_to_stdout if ::Rails.env.development?
        log_transport_to_rails

        configuration = Quicsilver::Transport::Configuration.new \
          certificate.cert_file, certificate.key_file,
          idle_timeout_ms: 120_000, keep_alive_interval_ms: 20_000, max_unidirectional_streams: 100,
          **transport_options

        server = Quicsilver::Server.new Integer(port), address: address, app: app, server_configuration: configuration
        server.shutdown_timeout = shutdown_timeout if shutdown_timeout && server.respond_to?(:shutdown_timeout=)

        Quicsilver.logger.info "listening on UDP #{address}:#{port}"
        server.start
      end

      # QUICSILVER_SHUTDOWN_TIMEOUT, in seconds: how long a graceful shutdown on INT or TERM may
      # take. Quicsilver's default is 30s; under foreman, which kills after 5s, it must be shorter.
      def shutdown_timeout_from_env
        value = ENV["QUICSILVER_SHUTDOWN_TIMEOUT"]
        Float(value) if value.present?
      end

      # `rails server` is what normally tees the log to the terminal, and this process doesn't go
      # through it. $stdout is synced because foreman reads it through a pipe, which otherwise
      # buffers the whole session.
      def log_to_stdout
        $stdout.sync = true

        unless ActiveSupport::Logger.logger_outputs_to?(::Rails.logger, $stdout)
          stdout = ActiveSupport::Logger.new($stdout).tap { |logger| logger.formatter = ::Rails.logger.formatter }
          ::Rails.logger.broadcast_to(stdout)
        end
      end

      # Without this the transport writes to its own $stdout logger: absent from log/<env>.log, in a
      # different format, and impossible to line up with the request it belongs to.
      # QUICSILVER_DEBUG=1 turns on the transport's detail.
      def log_transport_to_rails
        level = ENV["QUICSILVER_DEBUG"].present? ? Logger::DEBUG : Logger::INFO
        Quicsilver.logger = TransportLogger.new(::Rails.logger, level: level)
      end
    end
  end
end
