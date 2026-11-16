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

  def test_respects_the_target_level
    quiet = Logger.new(@output, level: Logger::WARN)
    Quicsilver::Rails::TransportLogger.new(quiet, level: Logger::DEBUG).info("connection opened")

    assert_empty @output.string
  end
end
