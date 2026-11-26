# frozen_string_literal: true

require "rails/generators"
require "quicsilver/rails/dev_web_transport_certificate"
require "quicsilver/rails/port"

module Quicsilver
  module Generators
    # Sets an app up to serve HTTP/3 in development, with Action Cable over WebTransport:
    #
    #   bin/rails generate quicsilver:install
    #   bin/dev-http3
    #
    # Every change is a file the app can read and edit. Running it again changes nothing that's
    # already in place.
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Serve the app over HTTP/3 in development, with Action Cable over WebTransport."

      LAYOUT = "app/views/layouts/application.html.erb"
      APPLICATION_JS = "app/javascript/application.js"
      META_TAGS = "<%= quicsilver_meta_tags %>"
      CABLE_BOOT = 'import "quicsilver/cable_boot"'

      def create_server_script
        template "quicsilver.tt", "bin/quicsilver"
        chmod "bin/quicsilver", 0o755
      end

      def create_dev_script
        template "dev-http3.tt", "bin/dev-http3"
        chmod "bin/dev-http3", 0o755
      end

      def create_procfile
        template "Procfile.http3.dev.tt", "Procfile.http3.dev"
      end

      def add_meta_tags_to_layout
        if app_file?(LAYOUT)
          insert_into_file LAYOUT, "    #{META_TAGS}\n", before: %r{^\s*</head>}
        else
          say_status :skip, "No #{LAYOUT}: add #{META_TAGS} to your layout's <head>", :yellow
        end
      end

      # The import has to come before Turbo, which captures the WebSocket class as it loads.
      def import_cable_boot
        if app_file?(APPLICATION_JS) && app_file?("config/importmap.rb")
          prepend_to_file APPLICATION_JS, "#{CABLE_BOOT} // must come before Turbo\n"
        else
          say_status :skip, "No importmap: import quicsilver/cable_boot before Turbo in your JavaScript", :yellow
        end
      end

      def show_next_steps
        say <<~MESSAGE

          Run bin/dev-http3, and open https://localhost:#{Quicsilver::Rails::DEFAULT_PORT}.

          WebTransport cables carry the Rails session cookie and session_id. If your
          ApplicationCable::Connection reads a different cookie, name it in config/application.rb:

            config.quicsilver.cable_cookies = %i[your_cookie]
        MESSAGE
      end

      private
        def app_file?(path)
          File.exist?(File.join(destination_root, path))
        end

        # Paths the gem generates the certificate at, so Puma's SSL bind reads the same files.
        def certificate_path(name)
          File.join(Quicsilver::Rails::DevWebTransportCertificate::DIRECTORY,
            Quicsilver::Rails::DevWebTransportCertificate.const_get(name))
        end

        # The app's other development processes, such as asset watchers, so they keep running.
        def other_dev_processes
          return [] unless app_file?("Procfile.dev")

          File.readlines(File.join(destination_root, "Procfile.dev"), chomp: true)
            .grep(/\A\s*[\w-]+:/).grep_v(/\A\s*web:/)
        end
    end
  end
end
