# frozen_string_literal: true

require "base64"
require "fileutils"
require "ipaddr"
require "openssl"
require "pathname"
require "securerandom"

module Quicsilver
  module Rails
    class DevWebTransportCertificate
      # WebTransport's serverCertificateHashes rejects a certificate valid for more than two weeks
      # (W3C WebTransport, "the total length of the validity period MUST NOT exceed two weeks").
      # A day short of that leaves room for clock skew.
      VALIDITY_SECONDS = 13 * 24 * 60 * 60
      REGENERATE_WITHIN_SECONDS = 24 * 60 * 60

      # Relative to Rails.root. Puma's SSL bind reads the same files, so the install generator writes
      # these into Procfile.http3.dev rather than its own copy.
      DIRECTORY = "tmp/quicsilver/webtransport"
      CERT_FILE_NAME = "localhost.pem"
      KEY_FILE_NAME = "localhost-key.pem"

      attr_reader :directory

      def self.fetch(directory: default_directory)
        new(directory: directory).tap(&:ensure!)
      end

      def self.default_directory
        ::Rails.root.join(DIRECTORY)
      end

      def initialize(directory:)
        @directory = Pathname(directory)
      end

      def cert_file
        directory.join(CERT_FILE_NAME).to_s
      end

      def key_file
        directory.join(KEY_FILE_NAME).to_s
      end

      def sha256
        ensure!
        Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(certificate.to_der))
      end

      # Signed by itself rather than a local CA such as mkcert's: browsers reject it, so the HTTPS page
      # shows a warning and its Alt-Svc is ignored.
      def self_signed?
        certificate.issuer == certificate.subject
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

        DEFAULT_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

        def generate!
          FileUtils.mkdir_p(directory)

          key = OpenSSL::PKey::EC.generate("prime256v1")
          root_cert, root_key = mkcert_root
          issuer = root_cert ? root_cert.subject : OpenSSL::X509::Name.parse("/CN=localhost")
          signing_key = root_key || key

          cert = OpenSSL::X509::Certificate.new
          cert.version = 2
          cert.serial = SecureRandom.random_number(2**64)
          cert.subject = OpenSSL::X509::Name.parse("/CN=localhost")
          cert.issuer = issuer
          cert.public_key = key
          cert.not_before = Time.now - 60
          cert.not_after = Time.now + VALIDITY_SECONDS

          extensions = OpenSSL::X509::ExtensionFactory.new
          extensions.subject_certificate = cert
          extensions.issuer_certificate = root_cert || cert
          cert.add_extension extensions.create_extension("basicConstraints", "CA:FALSE", true)
          cert.add_extension extensions.create_extension("keyUsage", "digitalSignature", true)
          cert.add_extension extensions.create_extension("extendedKeyUsage", "serverAuth", false)
          cert.add_extension extensions.create_extension("subjectAltName", subject_alt_name, false)
          cert.sign(signing_key, OpenSSL::Digest::SHA256.new)

          File.write(cert_file, cert.to_pem)
          File.write(key_file, key.to_pem)
        end

        def subject_alt_name
          dev_hosts.map { |host| ip_address?(host) ? "IP:#{host}" : "DNS:#{host}" }.join(",")
        end

        def dev_hosts
          ENV.fetch("QUICSILVER_DEV_HOSTS", DEFAULT_HOSTS.join(",")).split(",").map(&:strip).reject(&:empty?)
        end

        def ip_address?(host)
          IPAddr.new(host)
          true
        rescue IPAddr::InvalidAddressError
          false
        end

        def mkcert_root
          root = mkcert_caroot
          return [nil, nil] unless root

          cert_path = File.join(root, "rootCA.pem")
          key_path = File.join(root, "rootCA-key.pem")
          return [nil, nil] unless File.exist?(cert_path) && File.exist?(key_path)

          [
            OpenSSL::X509::Certificate.new(File.read(cert_path)),
            OpenSSL::PKey.read(File.read(key_path))
          ]
        rescue StandardError => error
          # The fallback is a certificate browsers reject, so say why rather than leave it to be found.
          # Rails' logger rather than Quicsilver's: this runs before Server.start routes the latter.
          ::Rails.logger&.warn "Could not use the mkcert CA at #{root}: #{error.class}: #{error.message}. " \
            "Using a self-signed certificate instead, which browsers reject; run `mkcert -install`."
          [nil, nil]
        end

        def mkcert_caroot
          return ENV["CAROOT"] if ENV["CAROOT"] && !ENV["CAROOT"].empty?
          return unless system("which mkcert > /dev/null 2>&1")

          root = `mkcert -CAROOT 2>/dev/null`.strip
          root unless root.empty?
        rescue StandardError
          nil
        end
    end
  end
end
