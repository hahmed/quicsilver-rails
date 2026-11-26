# frozen_string_literal: true

require "test_helper"

class QuicsilverRailsServerTest < Minitest::Test
  FakeServer = Struct.new(:shutdown_timeout, :started) do
    def start = self.started = true
  end

  Certificate = Struct.new(:cert_file, :key_file)

  ENV_KEYS = %w[QUICSILVER_SHUTDOWN_TIMEOUT QUICSILVER_PORT].freeze

  def setup
    @previous = ENV_KEYS.to_h { |key| [ key, ENV.delete(key) ] }
  end

  def teardown
    @previous.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
  end

  def test_binds_quicsilver_port
    ENV["QUICSILVER_PORT"] = "443"

    assert_equal 443, start(FakeServer.new)
  end

  def test_binds_3443_without_quicsilver_port
    assert_equal 3443, start(FakeServer.new)
  end

  def test_shutdown_timeout_comes_from_the_environment
    ENV["QUICSILVER_SHUTDOWN_TIMEOUT"] = "3"

    assert_equal 3.0, Quicsilver::Rails::Server.shutdown_timeout_from_env
  end

  def test_no_shutdown_timeout_leaves_quicsilvers_default
    assert_nil Quicsilver::Rails::Server.shutdown_timeout_from_env

    ENV["QUICSILVER_SHUTDOWN_TIMEOUT"] = ""
    assert_nil Quicsilver::Rails::Server.shutdown_timeout_from_env
  end

  def test_a_malformed_shutdown_timeout_fails_at_boot
    ENV["QUICSILVER_SHUTDOWN_TIMEOUT"] = "soon"

    assert_raises(ArgumentError) { Quicsilver::Rails::Server.shutdown_timeout_from_env }
  end

  def test_start_applies_the_shutdown_timeout_to_the_server
    server = FakeServer.new
    start(server, shutdown_timeout: 3.0)

    assert_equal 3.0, server.shutdown_timeout
    assert server.started
  end

  def test_start_without_a_shutdown_timeout_leaves_the_server_alone
    server = FakeServer.new
    start(server, shutdown_timeout: nil)

    assert_nil server.shutdown_timeout
  end

  private

  # Starts with the transport stubbed out, and returns the port the server was built to bind.
  def start(server, **options)
    bound = nil
    Quicsilver::Transport::Configuration.stub(:new, Object.new) do
      Quicsilver::Server.stub(:new, ->(port, **) { bound = port; server }) do
        Quicsilver::Rails::Server.stub(:log_transport_to_rails, nil) do
          ::Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("test")) do
            Quicsilver::Rails::Server.start(app: Object.new, certificate: Certificate.new("c", "k"), **options)
          end
        end
      end
    end
    bound
  end
end
