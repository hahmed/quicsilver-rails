# frozen_string_literal: true

require "rails/engine"

module Quicsilver
  class Engine < ::Rails::Engine
    config.quicsilver = ActiveSupport::OrderedOptions.new

    initializer "quicsilver.executor" do |app|
      config.quicsilver.executor ||= app.executor
    end
  end
end
