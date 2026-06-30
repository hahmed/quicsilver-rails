# frozen_string_literal: true

require "rails/engine"

module Quicsilver
  class Engine < ::Rails::Engine
    config.quicsilver = ActiveSupport::OrderedOptions.new

    initializer "quicsilver.executor" do |app|
      config.quicsilver.executor ||= app.executor
    end

    initializer "quicsilver.action_cable", after: "action_cable.set_configs" do
      ActiveSupport.on_load(:action_cable) do
        Quicsilver::ActionCable.install!
      end
    end
  end
end
