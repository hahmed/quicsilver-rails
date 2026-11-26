# frozen_string_literal: true

require "rails/engine"
require "quicsilver/routes"

module Quicsilver
  class Engine < ::Rails::Engine
    config.quicsilver = ActiveSupport::OrderedOptions.new

    # Runs each WebTransport endpoint's long-lived work; swap in another runner (fibers, say) here.
    initializer "quicsilver.webtransport_runner" do
      config.quicsilver.webtransport_runner ||= Quicsilver::WebTransport::ThreadRunner.new
    end

    initializer "quicsilver.routes" do
      ActionDispatch::Routing::Mapper.include Quicsilver::Routes
    end

    initializer "quicsilver.assets" do |app|
      app.config.assets.paths << root.join("app/javascript").to_s if app.config.respond_to?(:assets)
    end

    initializer "quicsilver.importmap", before: "importmap" do |app|
      app.config.importmap.paths << root.join("config/importmap.rb") if app.config.respond_to?(:importmap)
    end

    initializer "quicsilver.alt_svc" do |app|
      if (options = Quicsilver::Middleware::AltSvc.options_for(app.config.quicsilver.alt_svc))
        app.middleware.insert_before 0, Quicsilver::Middleware::AltSvc, **options
      end
    end

    initializer "quicsilver.request_protocol" do
      ActiveSupport.on_load(:action_dispatch_request) do
        include Quicsilver::Rails::RequestProtocol
      end
    end

    initializer "quicsilver.web_transport_certificate_helper" do
      ActiveSupport.on_load(:action_view) do
        include Quicsilver::Rails::WebTransportCertificateHelper
        include Quicsilver::Rails::CableCredentialHelper
        include Quicsilver::Rails::MetaTagsHelper
      end
    end

    initializer "quicsilver.action_cable", after: "action_cable.set_configs" do
      ActiveSupport.on_load(:action_cable) do
        Quicsilver::ActionCable.install!
      end
    end
  end
end
