# frozen_string_literal: true

require "quicsilver"
require "quicsilver/rails/dev_web_transport_certificate"

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
                **transport_options)
        log_to_stdout if ::Rails.env.development?

        configuration = Quicsilver::Transport::Configuration.new \
          certificate.cert_file, certificate.key_file,
          idle_timeout_ms: 120_000, keep_alive_interval_ms: 20_000, max_unidirectional_streams: 100,
          **transport_options

        server = Quicsilver::Server.new Integer(port), address: address, app: app, server_configuration: configuration

        ::Rails.logger.info "Quicsilver listening on UDP #{address}:#{port}"
        server.start
      end

      # `rails server` is what normally tees the log to the terminal, and this process doesn't go
      # through it. $stdout is synced because foreman reads it through a pipe, which otherwise
      # buffers the whole session. QUICSILVER_DEBUG=1 turns on the transport's own log:
      # handshakes, WebTransport sessions, stream resets.
      def log_to_stdout
        $stdout.sync = true

        unless ActiveSupport::Logger.logger_outputs_to?(::Rails.logger, $stdout)
          stdout = ActiveSupport::Logger.new($stdout).tap { |logger| logger.formatter = ::Rails.logger.formatter }
          ::Rails.logger.broadcast_to(stdout)
        end

        Quicsilver.logger.level = ENV["QUICSILVER_DEBUG"].present? ? Logger::DEBUG : Logger::INFO
      end
    end
  end
end
