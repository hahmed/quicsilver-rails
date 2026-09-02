# frozen_string_literal: true

require "test_helper"
require "quicsilver/web_transport/channel"

class QuicsilverWebTransportChannelTest < Minitest::Test
  RawStream = WebTransportDoubles::RawStream

  Session = WebTransportDoubles::Session

  class ReactionCommand
    def self.call(message)
      { type: "event", emoji: message.fetch("emoji") }
    end
  end

  class ActivityStream
    def self.call(stream:, codec:, session:, message:)
      stream.write_message codec.encode(type: "snapshot", requested: message.fetch("type"), open: session.open?)
      stream.close
    end
  end

  class DropChannel < Quicsilver::WebTransport::Channel
    attr_reader :datagrams

    def initialize(*)
      super
      @datagrams = []
    end

    datagram do |packet|
      datagrams << packet
    end
  end

  class RawChannel < Quicsilver::WebTransport::Channel
    codec :raw
  end

  class InheritedCodecChannel < RawChannel; end

  class RegistryChannel < Quicsilver::WebTransport::Channel
    command "reaction", to: ReactionCommand
    stream "subscribe", to: ActivityStream
  end

  class ChildRegistryChannel < RegistryChannel
    command "claim", to: ReactionCommand
  end

  # === codec ===
  #
  # Every other endpoint exposes a codec macro; Channel used to hardcode JSON,
  # so a channel could not speak msgpack or raw bytes.

  def test_defaults_to_json
    assert_equal :json, Quicsilver::WebTransport::Channel.codec
  end

  def test_codec_is_configurable
    assert_equal :raw, RawChannel.codec
  end

  def test_subclasses_inherit_the_codec
    assert_equal :raw, InheritedCodecChannel.codec
  end

  def test_setting_a_codec_does_not_leak_to_siblings
    assert_equal :json, DropChannel.codec
  end

  def test_resolves_the_configured_codec_at_runtime
    channel = RawChannel.new("quicsilver.webtransport" => Session.new)

    assert_equal Quicsilver::WebTransport::Codec::Raw, channel.send(:codec)
  end

  def test_resolves_json_by_default_at_runtime
    channel = DropChannel.new("quicsilver.webtransport" => Session.new)

    assert_equal Quicsilver::WebTransport::Codec::JSON, channel.send(:codec)
  end

  # === registries ===

  def test_subclasses_inherit_commands_and_streams
    assert_equal ReactionCommand, ChildRegistryChannel.commands["reaction"]
    assert_equal ActivityStream, ChildRegistryChannel.streams["subscribe"]
  end

  def test_subclass_additions_do_not_leak_to_the_parent
    assert_equal ReactionCommand, ChildRegistryChannel.commands["claim"]
    refute RegistryChannel.commands.key?("claim")
  end

  def test_dispatches_command_streams_by_message_type
    raw_stream = RawStream.new(JSON.generate(type: "reaction", emoji: "🔥"))

    dispatcher.call(raw_stream)

    assert raw_stream.closed
    assert_equal [{ "type" => "event", "emoji" => "🔥" }], raw_stream.json_messages
  end

  def test_dispatches_live_streams_by_message_type
    raw_stream = RawStream.new(JSON.generate(type: "subscribe"))

    dispatcher.call(raw_stream)

    assert raw_stream.closed
    assert_equal [{ "type" => "snapshot", "requested" => "subscribe", "open" => true }], raw_stream.json_messages
  end

  def test_unknown_message_type_returns_structured_error
    raw_stream = RawStream.new(JSON.generate(type: "unknown"))

    dispatcher.call(raw_stream)

    assert raw_stream.closed
    assert_equal [{ "type" => "error", "error" => "Unknown WebTransport message type: unknown" }], raw_stream.json_messages
  end

  def test_handles_datagrams_in_channel_context
    channel = DropChannel.new({})

    channel.send(:handle_datagram, "hype")

    assert_equal ["hype"], channel.datagrams
  end

  private
    def dispatcher
      Quicsilver::WebTransport::Channel::Dispatcher.new(
        commands: { "reaction" => ReactionCommand },
        streams: { "subscribe" => ActivityStream },
        codec: Quicsilver::WebTransport::Codec.resolve(:json),
        session: Session.new
      )
    end
end
