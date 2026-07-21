# frozen_string_literal: true

require "rails/engine"
require "quicsilver/routes"

module Quicsilver
  class Engine < ::Rails::Engine
    config.quicsilver = ActiveSupport::OrderedOptions.new

    initializer "quicsilver.executor" do |app|
      config.quicsilver.executor ||= app.executor
      config.quicsilver.webtransport_runner ||= Quicsilver::WebTransport::ThreadRunner.new
    end

    initializer "quicsilver.routes" do
      ActionDispatch::Routing::Mapper.include Quicsilver::Routes
    end

    initializer "quicsilver.alt_svc" do |app|
      next unless app.config.quicsilver.alt_svc

      options = app.config.quicsilver.alt_svc == true ? {} : app.config.quicsilver.alt_svc
      app.middleware.insert_before 0, Quicsilver::Middleware::AltSvc, **options
    end

    initializer "quicsilver.web_transport_certificate_helper" do
      ActiveSupport.on_load(:action_view) do
        include Quicsilver::Rails::WebTransportCertificateHelper
      end
    end

    initializer "quicsilver.action_cable", after: "action_cable.set_configs" do
      ActiveSupport.on_load(:action_cable) do
        Quicsilver::ActionCable.install!
      end
    end
  end
end
