# frozen_string_literal: true

require "test_helper"
require "stringio"

class QuicsilverActionCableInstallTest < Minitest::Test
  def setup
    @installed = Quicsilver::ActionCable.instance_variable_get(:@installed)
    Quicsilver::ActionCable.instance_variable_set(:@installed, false)
  end

  def teardown
    Quicsilver::ActionCable.instance_variable_set(:@installed, @installed)
  end

  def test_rails_main_has_the_socket_seam
    assert Quicsilver::ActionCable.available?
  end

  def test_without_the_seam_install_warns_once_and_leaves_sockets_alone
    log = StringIO.new
    logger = Logger.new(log)

    Quicsilver::ActionCable.stub(:available?, false) do
      ::ActionCable::Server::Socket.stub(:prepend, ->(*) { flunk "nothing to plug into without the seam" }) do
        Quicsilver::ActionCable.install!(logger: logger)
        Quicsilver::ActionCable.install!(logger: logger)
      end
    end

    assert_equal 1, log.string.scan("needs Rails main").size
    assert_includes log.string, "cables stay on WebSocket"
  end

  def test_without_the_seam_connections_still_answer_for_a_credential
    Quicsilver::ActionCable.stub(:available?, false) do
      Quicsilver::ActionCable.install!(logger: Logger.new(nil))
    end

    assert_includes ::ActionCable::Connection::Base.private_instance_methods, :quicsilver_cable_credential
  end
end
