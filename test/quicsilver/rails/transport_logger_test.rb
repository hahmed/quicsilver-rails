# frozen_string_literal: true

require "test_helper"
require "stringio"

class TransportLoggerTest < Minitest::Test
  def setup
    @output = StringIO.new
    @target = Logger.new(@output, level: Logger::DEBUG)
  end

  def test_writes_through_the_target_with_a_tag
    Quicsilver::Rails::TransportLogger.new(@target).info("handshake complete")

    assert_includes @output.string, "[quicsilver] handshake complete"
  end

  def test_keeps_its_own_level
    logger = Quicsilver::Rails::TransportLogger.new(@target, level: Logger::INFO)
    logger.debug("stream=4 headers")

    assert_empty @output.string
  end

  def test_evaluates_blocks_only_when_logging
    logger = Quicsilver::Rails::TransportLogger.new(@target, level: Logger::INFO)
    called = false
    logger.debug { called = true }
    logger.debug("ignored") { called = true }

    refute called
  end

  # protocol-rack logs through the console gem, not Quicsilver.logger. Its error line, when a Rack app
  # raises, has to reach the Rails log rather than stderr.
  def test_the_rack_adapters_error_reaches_the_rails_log
    rails_log = with_transport_logged_to_rails do
      Quicsilver::Server::RackAdapter.new(->(_env) { [200, {}, []] })
        .handle_error({}, nil, nil, nil, RuntimeError.new("boom"))
    end

    assert_includes rails_log, "[quicsilver] Quicsilver::Server::RackAdapter Error occurred during request processing: RuntimeError: boom"
  end

  def test_console_detail_follows_the_transport_level
    rails_log = with_transport_logged_to_rails { Console.debug(self, "stream detail") }

    refute_includes rails_log, "stream detail", "debug needs QUICSILVER_DEBUG"
  end

  def test_respects_the_target_level
    quiet = Logger.new(@output, level: Logger::WARN)
    Quicsilver::Rails::TransportLogger.new(quiet, level: Logger::DEBUG).info("connection opened")

    assert_empty @output.string
  end

  private
    # Wires logging the way Quicsilver::Rails::Server.start does, runs the block, and returns what
    # reached the Rails log. Both loggers are process-wide, so they are put back afterwards.
    def with_transport_logged_to_rails
      previous = [ Quicsilver.logger, Console.logger ]
      output = StringIO.new
      ::Rails.stub(:logger, Logger.new(output)) { Quicsilver::Rails::Server.log_transport_to_rails }
      yield
      output.string
    ensure
      Quicsilver.logger, Console.logger = previous
    end
end
