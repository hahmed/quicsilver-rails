# frozen_string_literal: true

require "quicsilver/rails/dev_web_transport_certificate"

module Quicsilver
  module Rails
    module WebTransportCertificateHelper
      META_NAME = "quicsilver-webtransport-certificate-sha256"

      def quicsilver_webtransport_certificate_meta_tag
        return unless ::Rails.env.development?

        certificate = DevWebTransportCertificate.fetch
        tag.meta(name: META_NAME, content: certificate.sha256)
      end
    end
  end
end
