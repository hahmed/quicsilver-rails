# frozen_string_literal: true

require "test_helper"

# Typed message support shared by every endpoint.
#
# `receives SomeType` lets an endpoint work with domain objects instead of
# hashes. MessageCodec decides how to get there, preferring a type's own
# decode/encode, then load/dump, then falling back to the wire codec.
class QuicsilverWebTransportMessageCodecTest < Minitest::Test
  # Defines its own decode/encode — highest precedence.
  class SelfCoding
    attr_reader :value

    def initialize(value) = @value = value

    def self.decode(payload) = new("decoded:#{payload}")
    def self.encode(value) = "encoded:#{value}"
  end

  # Marshal-style load/dump — used when decode/encode are absent.
  class LoadDumping
    attr_reader :value

    def initialize(value) = @value = value

    def self.load(payload) = new("loaded:#{payload}")
    def self.dump(value) = "dumped:#{value}"
  end

  # Neither — constructed from the codec-decoded payload.
  class PlainType
    attr_reader :attributes

    def initialize(attributes) = @attributes = attributes
  end

  class Host
    include Quicsilver::WebTransport::MessageCodec

    def self.codec = :json

    # MessageCodec's methods are private; expose them for testing.
    public :decode_with, :encode_with, :codec
  end

  def setup
    @host = Host.new
  end

  # === decode ===

  def test_decodes_through_the_wire_codec_when_no_type_is_given
    assert_equal({ "a" => 1 }, @host.decode_with(nil, '{"a":1}'))
  end

  def test_prefers_a_types_own_decode
    result = @host.decode_with(SelfCoding, "payload")

    assert_instance_of SelfCoding, result
    assert_equal "decoded:payload", result.value
  end

  def test_falls_back_to_load
    result = @host.decode_with(LoadDumping, "payload")

    assert_instance_of LoadDumping, result
    assert_equal "loaded:payload", result.value
  end

  # Last resort: decode the wire format, then hand it to the constructor.
  def test_constructs_from_the_decoded_payload
    result = @host.decode_with(PlainType, '{"a":1}')

    assert_instance_of PlainType, result
    assert_equal({ "a" => 1 }, result.attributes)
  end

  # === encode ===

  def test_encodes_through_the_wire_codec_when_no_type_is_given
    assert_equal '{"a":1}', @host.encode_with(nil, { a: 1 })
  end

  def test_prefers_a_types_own_encode
    assert_equal "encoded:hello", @host.encode_with(SelfCoding, "hello")
  end

  def test_falls_back_to_dump
    assert_equal "dumped:hello", @host.encode_with(LoadDumping, "hello")
  end

  # A type with neither still has to reach the wire somehow.
  def test_encodes_through_the_wire_codec_for_a_plain_type
    assert_equal '{"a":1}', @host.encode_with(PlainType, { a: 1 })
  end

  # === codec resolution ===

  def test_resolves_the_hosts_codec
    assert_equal Quicsilver::WebTransport::Codec::JSON, @host.codec
  end

  def test_memoises_the_codec
    assert_same @host.codec, @host.codec
  end

  # === round trip ===

  def test_round_trips_through_a_self_coding_type
    encoded = @host.encode_with(SelfCoding, "x")

    assert_equal "decoded:encoded:x", @host.decode_with(SelfCoding, encoded).value
  end
end
