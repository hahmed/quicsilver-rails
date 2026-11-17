# frozen_string_literal: true

require "test_helper"

class QuicsilverRailsServerTest < Minitest::Test
  FakeServer = Struct.new(:shutdown_timeout, :started) do
    def start = self.started = true
  end

  Certificate = Struct.new(:cert_file, :key_file)

  def setup
    @previous = ENV.delete("QUICSILVER_SHUTDOWN_TIMEOUT")
  end

  def teardown
    @previous ? ENV["QUICSILVER_SHUTDOWN_TIMEOUT"] = @previous : ENV.delete("QUICSILVER_SHUTDOWN_TIMEOUT")
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

  def start(server, shutdown_timeout:)
    Quicsilver::Transport::Configuration.stub(:new, Object.new) do
      Quicsilver::Server.stub(:new, server) do
        Quicsilver::Rails::Server.stub(:log_transport_to_rails, nil) do
          ::Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("test")) do
            Quicsilver::Rails::Server.start(app: Object.new, port: 0, certificate: Certificate.new("c", "k"),
              shutdown_timeout: shutdown_timeout)
          end
        end
      end
    end
  end
end
