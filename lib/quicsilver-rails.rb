# frozen_string_literal: true

require "quicsilver"

require "quicsilver/rails/version"
require "quicsilver/web_transport"
require "quicsilver/routes"
require "quicsilver/middleware/alt_svc"
require "quicsilver/action_cable"
require "quicsilver/engine" if defined?(::Rails::Railtie)
