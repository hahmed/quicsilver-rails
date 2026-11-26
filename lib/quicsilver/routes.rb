# frozen_string_literal: true

module Quicsilver
  module Routes
    # Mount a Rack-callable Quicsilver WebTransport endpoint.
    #
    #   webtransport "/cursors", to: CursorTransport
    #
    # Endpoint classes such as Quicsilver::WebTransport::DatagramEndpoint,
    # RpcEndpoint, and ServerStreamingEndpoint implement .call(env), so they can be mounted
    # directly through Rails routing.
    def webtransport(path, to:, **options)
      match path, to: webtransport_endpoint(to), via: :all, **options
    end

    private

    # A class named by string is looked up per request, not when routes are drawn, so a reload in
    # development serves the new class rather than the one the routes captured.
    def webtransport_endpoint(to)
      return to if to.respond_to?(:call)

      name = to.to_s.camelize
      ->(env) { name.constantize.call(env) }
    end
  end
end
