# frozen_string_literal: true

require "base64"
require "fileutils"
require "openssl"
require "pathname"
require "securerandom"

module Quicsilver
  module Rails
    class DevWebTransportCertificate
      VALIDITY_SECONDS = 13 * 24 * 60 * 60
      REGENERATE_WITHIN_SECONDS = 24 * 60 * 60

      attr_reader :directory

      def self.fetch(directory: default_directory)
        new(directory: directory).tap(&:ensure!)
      end

      def self.default_directory
        ::Rails.root.join("tmp/quicsilver/webtransport")
      end

      def initialize(directory:)
        @directory = Pathname(directory)
      end

      def cert_file
        directory.join("localhost.pem").to_s
      end

      def key_file
        directory.join("localhost-key.pem").to_s
      end

      def sha256
        ensure!
        Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(certificate.to_der))
      end

      def ensure!
        return if usable?

        generate!
      end

      private
        def usable?
          return false unless File.exist?(cert_file) && File.exist?(key_file)

          certificate.not_after > Time.now + REGENERATE_WITHIN_SECONDS
        rescue OpenSSL::X509::CertificateError
          false
        end

        def certificate
          OpenSSL::X509::Certificate.new(File.read(cert_file))
        end

        def generate!
          FileUtils.mkdir_p(directory)

          key = OpenSSL::PKey::EC.generate("prime256v1")
          cert = OpenSSL::X509::Certificate.new
          cert.version = 2
          cert.serial = SecureRandom.random_number(2**64)
          cert.subject = OpenSSL::X509::Name.parse("/CN=localhost")
          cert.issuer = cert.subject
          cert.public_key = key
          cert.not_before = Time.now - 60
          cert.not_after = Time.now + VALIDITY_SECONDS

          extensions = OpenSSL::X509::ExtensionFactory.new
          extensions.subject_certificate = cert
          extensions.issuer_certificate = cert
          cert.add_extension extensions.create_extension("basicConstraints", "CA:FALSE", true)
          cert.add_extension extensions.create_extension("keyUsage", "digitalSignature", true)
          cert.add_extension extensions.create_extension("extendedKeyUsage", "serverAuth", false)
          cert.add_extension extensions.create_extension("subjectAltName", "DNS:localhost,IP:127.0.0.1,IP:::1", false)
          cert.sign(key, OpenSSL::Digest::SHA256.new)

          File.write(cert_file, cert.to_pem)
          File.write(key_file, key.to_pem)
        end
    end
  end
end
