# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "active_support/testing/time_helpers"

# The certificate both listeners serve in development. When it is wrong nothing raises: the browser
# refuses the HTTP/3 listener and quietly stays on TCP. So these check the certificate itself.
class DevWebTransportCertificateTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  Certificate = Quicsilver::Rails::DevWebTransportCertificate
  ENV_KEYS = %w[CAROOT QUICSILVER_DEV_HOSTS].freeze
  TWO_WEEKS = 14 * 24 * 60 * 60

  def setup
    @previous_env = ENV_KEYS.to_h { |key| [ key, ENV.delete(key) ] }
    @directory = Dir.mktmpdir("quicsilver-certificate")
    # An empty CA root: no mkcert CA, so the certificate signs itself unless a test provides one.
    ENV["CAROOT"] = Dir.mktmpdir("quicsilver-caroot")
  end

  def teardown
    @previous_env.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
    FileUtils.rm_rf(@directory)
  end

  def test_generates_a_certificate_and_key_that_belong_together
    certificate = Certificate.fetch(directory: @directory)

    assert certificate_at(certificate).check_private_key(OpenSSL::PKey.read(File.read(certificate.key_file)))
  end

  # WebTransport's serverCertificateHashes rejects certificates valid for more than two weeks.
  def test_is_valid_for_no_more_than_two_weeks
    x509 = certificate_at(Certificate.fetch(directory: @directory))

    assert_operator x509.not_after - x509.not_before, :<=, TWO_WEEKS
  end

  def test_covers_the_default_local_hosts
    assert_equal %w[DNS:localhost IP:127.0.0.1 IP:0:0:0:0:0:0:0:1], subject_alt_names(Certificate.fetch(directory: @directory))
  end

  def test_covers_the_configured_hosts_with_ip_addresses_as_ip_entries
    ENV["QUICSILVER_DEV_HOSTS"] = "app.test, 10.0.0.5, fe80::a"

    assert_equal %w[DNS:app.test IP:10.0.0.5 IP:FE80:0:0:0:0:0:0:A], subject_alt_names(Certificate.fetch(directory: @directory))
  end

  def test_reuses_a_certificate_that_is_still_valid
    first = Certificate.fetch(directory: @directory).sha256

    assert_equal first, Certificate.fetch(directory: @directory).sha256
  end

  def test_replaces_a_certificate_about_to_expire
    first = Certificate.fetch(directory: @directory).sha256

    travel(13 * 24 * 60 * 60) do
      refute_equal first, Certificate.fetch(directory: @directory).sha256
    end
  end

  def test_replaces_a_certificate_file_that_cannot_be_read
    Certificate.fetch(directory: @directory)
    File.write(File.join(@directory, "localhost.pem"), "not a certificate")

    assert_kind_of OpenSSL::X509::Certificate, certificate_at(Certificate.fetch(directory: @directory))
  end

  # Signed by the local mkcert CA, which the browser already trusts.
  def test_is_signed_by_the_mkcert_root_when_there_is_one
    root_certificate, root_key = write_root_ca(ENV["CAROOT"])

    x509 = certificate_at(Certificate.fetch(directory: @directory))

    assert_equal root_certificate.subject, x509.issuer
    assert x509.verify(root_key)
    refute Certificate.fetch(directory: @directory).self_signed?
  end

  def test_signs_itself_without_an_mkcert_root
    certificate = Certificate.fetch(directory: @directory)
    x509 = certificate_at(certificate)

    assert_equal x509.subject, x509.issuer
    assert certificate.self_signed?
  end

  # A self-signed certificate is one the browser will reject, so falling back to it must be visible.
  def test_says_why_when_the_mkcert_root_cannot_be_used
    write_root_ca(ENV["CAROOT"])
    File.write(File.join(ENV["CAROOT"], "rootCA-key.pem"), "not a key")

    log = with_logged { Certificate.fetch(directory: @directory) }

    assert_match(/mkcert CA at #{Regexp.escape(ENV["CAROOT"])}/, log)
    assert_match(/self-signed/, log)
  end

  private
    def certificate_at(certificate)
      OpenSSL::X509::Certificate.new(File.read(certificate.cert_file))
    end

    def subject_alt_names(certificate)
      certificate_at(certificate).extensions.find { _1.oid == "subjectAltName" }.value
        .split(",").map { _1.strip.sub("IP Address:", "IP:") }
    end

    def write_root_ca(directory)
      key = OpenSSL::PKey::EC.generate("prime256v1")
      certificate = OpenSSL::X509::Certificate.new
      certificate.version = 2
      certificate.serial = 1
      certificate.subject = certificate.issuer = OpenSSL::X509::Name.parse("/CN=test root")
      certificate.public_key = key
      certificate.not_before = Time.now - 60
      certificate.not_after = Time.now + 365 * 24 * 60 * 60
      certificate.sign(key, OpenSSL::Digest::SHA256.new)
      File.write(File.join(directory, "rootCA.pem"), certificate.to_pem)
      File.write(File.join(directory, "rootCA-key.pem"), key.to_pem)
      [ certificate, key ]
    end

    def with_logged
      output = StringIO.new
      ::Rails.stub(:logger, Logger.new(output)) { yield }
      output.string
    end
end
