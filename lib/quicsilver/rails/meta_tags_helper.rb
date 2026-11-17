# frozen_string_literal: true

module Quicsilver
  module Rails
    # Everything a page's <head> needs from quicsilver-rails, in one call:
    #
    #   <%= quicsilver_meta_tags %>
    #
    # On a page served over HTTP/3 it renders
    #
    # - the development certificate hash, so the browser accepts a local CA for WebTransport;
    # - the quicsilver-cable marker, which tells quicsilver/cable_boot to move the cable onto
    #   WebTransport, when this Rails can carry it there (Quicsilver::ActionCable.available?);
    # - the cable's cookies, encrypted, so #connect finds the session as it does over a WebSocket
    #   (see Quicsilver::ActionCable::CookieBridge);
    # - a separate cable credential, for apps that pass one.
    #
    # On a page served over TCP it renders nothing, and the cable stays on WebSocket.
    module MetaTagsHelper
      CABLE_META_NAME = "quicsilver-cable"
      COOKIES_META_NAME = "quicsilver-cable-cookies"

      def quicsilver_meta_tags(cable_credential: nil)
        safe_join [
          quicsilver_webtransport_certificate_meta_tag,
          quicsilver_cable_meta_tag,
          quicsilver_cable_cookies_meta_tag,
          quicsilver_cable_credential_meta_tag(cable_credential)
        ].compact, "\n"
      end

      # Tells quicsilver/cable_boot to move the cable onto WebTransport.
      def quicsilver_cable_meta_tag
        if quicsilver_cable_over_web_transport?
          tag.meta(name: CABLE_META_NAME, content: "webtransport")
        end
      end

      # The allowlisted cookies, encrypted, for the cable to send back in its handshake.
      def quicsilver_cable_cookies_meta_tag
        if quicsilver_cable_over_web_transport? && (token = Quicsilver::ActionCable.cookie_bridge&.token_for(request.cookies))
          tag.meta(name: COOKIES_META_NAME, content: token)
        end
      end

      private
        def quicsilver_cable_over_web_transport?
          request.http3? && Quicsilver::ActionCable.available?
        end
    end
  end
end
