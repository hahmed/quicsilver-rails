# frozen_string_literal: true

require "quicsilver/rails/dev_web_transport_certificate"

module Quicsilver
  module Rails
    module WebTransportCertificateHelper
      META_NAME = "quicsilver-webtransport-certificate-sha256"

      def quicsilver_webtransport_certificate_meta_tag
        # Development-only: the hash pins a local certificate. Only over HTTP/3, because its presence
        # is what tells cable_boot to move the cable onto WebTransport.
        return unless ::Rails.env.development? && request.http3?

        certificate = DevWebTransportCertificate.fetch
        tag.meta(name: META_NAME, content: certificate.sha256)
      end
    end
  end
end
