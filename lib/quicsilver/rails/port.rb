# frozen_string_literal: true

module Quicsilver
  module Rails
    DEFAULT_PORT = 3443

    # The UDP port the HTTP/3 listener binds, and so the port Alt-Svc advertises: QUICSILVER_PORT,
    # or 3443. One answer for both, because a browser pointed at the wrong port gets no reply and
    # stays on TCP without any error. In production that is usually 443, the UDP port networks let
    # through.
    def self.port
      Integer(ENV.fetch("QUICSILVER_PORT", DEFAULT_PORT))
    end
  end
end
