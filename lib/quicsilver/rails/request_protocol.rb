# frozen_string_literal: true

module Quicsilver
  module Rails
    # Included into ActionDispatch::Request.
    #
    # Whether this request arrived over HTTP/3, which is the only evidence that the client can reach
    # the HTTP/3 listener right now. Configuration says the server offers HTTP/3; a browser on its
    # first visit, or with UDP blocked, is still on TCP.
    module RequestProtocol
      def http3?
        get_header("SERVER_PROTOCOL") == "HTTP/3"
      end
    end
  end
end
