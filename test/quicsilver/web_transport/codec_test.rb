# frozen_string_literal: true

require "test_helper"

class QuicsilverWebTransportCodecTest < Minitest::Test
  Codec = Quicsilver::WebTransport::Codec

  # === resolve ===

  def test_resolves_nil_to_raw
    assert_equal Codec::Raw, Codec.resolve(nil)
  end

  def test_resolves_raw
    assert_equal Codec::Raw, Codec.resolve(:raw)
  end

  def test_resolves_json
    assert_equal Codec::JSON, Codec.resolve(:json)
  end

  # Anything else is assumed to already be a codec, so apps can pass their own
  # (msgpack, protobuf) without the gem knowing about it.
  def test_passes_through_a_custom_codec
    custom = Module.new do
      def self.decode(payload) = payload
      def self.encode(value) = value
    end

    assert_same custom, Codec.resolve(custom)
  end

  # === raw ===

  def test_raw_decode_returns_the_payload_unchanged
    assert_equal "hello", Codec::Raw.decode("hello")
  end

  def test_raw_encode_stringifies
    assert_equal "42", Codec::Raw.encode(42)
    assert_equal "hello", Codec::Raw.encode("hello")
  end

  def test_raw_round_trips_binary
    payload = "\x00\xFF\x01".b

    assert_equal payload, Codec::Raw.decode(Codec::Raw.encode(payload))
  end

  # === json ===

  def test_json_encodes_a_hash
    assert_equal({ "type" => "ping" }, JSON.parse(Codec::JSON.encode(type: "ping")))
  end

  def test_json_decodes_to_string_keys
    assert_equal({ "type" => "ping" }, Codec::JSON.decode('{"type":"ping"}'))
  end

  def test_json_round_trips
    value = { "type" => "reaction", "emoji" => "🔥", "count" => 3 }

    assert_equal value, Codec::JSON.decode(Codec::JSON.encode(value))
  end

  def test_json_raises_on_invalid_payload
    assert_raises(JSON::ParserError) { Codec::JSON.decode("not json") }
  end
end
