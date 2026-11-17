# frozen_string_literal: true

module Quicsilver
  module Rails
    # Everything a page's <head> needs from quicsilver-rails, in one call:
    #
    #   <%= quicsilver_meta_tags cable_credential: Current.session&.signed_id(purpose: :cable, expires_in: 1.day) %>
    #
    # On a page served over HTTP/3 it renders
    #
    # - the development certificate hash, so the browser accepts a local CA for WebTransport;
    # - the quicsilver-cable marker, which tells quicsilver/cable_boot to move the cable onto
    #   WebTransport, when this Rails can carry it there (Quicsilver::ActionCable.available?);
    # - the cable credential, when one is given.
    #
    # On a page served over TCP it renders nothing, and the cable stays on WebSocket.
    module MetaTagsHelper
      CABLE_META_NAME = "quicsilver-cable"

      def quicsilver_meta_tags(cable_credential: nil)
        safe_join [
          quicsilver_webtransport_certificate_meta_tag,
          quicsilver_cable_meta_tag,
          quicsilver_cable_credential_meta_tag(cable_credential)
        ].compact, "\n"
      end

      private
        def quicsilver_cable_meta_tag
          if request.http3? && Quicsilver::ActionCable.available?
            tag.meta(name: CABLE_META_NAME, content: "webtransport")
          end
        end
    end
  end
end
