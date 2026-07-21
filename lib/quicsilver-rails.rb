# frozen_string_literal: true

require "quicsilver"

require "quicsilver/rails/version"
require "quicsilver/web_transport"
require "quicsilver/routes"
require "quicsilver/middleware/alt_svc"
require "quicsilver/rails/dev_web_transport_certificate"
require "quicsilver/rails/web_transport_certificate_helper"
require "quicsilver/action_cable"
require "quicsilver/engine" if defined?(::Rails::Railtie)
