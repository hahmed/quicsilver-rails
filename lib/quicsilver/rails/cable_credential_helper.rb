# frozen_string_literal: true

module Quicsilver
  module Rails
    # Renders the credential a WebTransport cable sends in its handshake frame.
    #
    # Browsers send no cookies on a WebTransport CONNECT, so the page has to
    # hand the cable something to authenticate with. The app decides what: it
    # should be short-lived and purpose-scoped, so it cannot stand in for the
    # session cookie if it leaks, e.g.
    #
    #   <%= quicsilver_cable_credential_meta_tag Current.session&.signed_id(purpose: :cable, expires_in: 1.day) %>
    #
    # Renders nothing for a nil credential, so signed-out pages need no guard, and
    # nothing unless the app advertises HTTP/3 (config.quicsilver.alt_svc), so
    # the credential is never put in a page that can't use it.
    module CableCredentialHelper
      META_NAME = "quicsilver-cable-credential"

      def quicsilver_cable_credential_meta_tag(credential)
        if credential.present? && ::Rails.application.config.quicsilver.alt_svc
          tag.meta(name: META_NAME, content: credential)
        end
      end
    end
  end
end
