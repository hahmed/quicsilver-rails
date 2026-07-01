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
      endpoint = resolve_webtransport_endpoint(to)
      match path, to: endpoint, via: :all, **options
    end

    private

    def resolve_webtransport_endpoint(to)
      return to if to.respond_to?(:call)

      to.to_s.camelize.constantize
    end
  end
end
