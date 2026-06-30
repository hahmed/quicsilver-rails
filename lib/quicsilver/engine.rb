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
      ActiveSupport.on_load(:action_dispatch_routing) do
        include Quicsilver::Routes
      end
    end

    initializer "quicsilver.action_cable", after: "action_cable.set_configs" do
      ActiveSupport.on_load(:action_cable) do
        Quicsilver::ActionCable.install!
      end
    end
  end
end
