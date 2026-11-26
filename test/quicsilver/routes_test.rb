# frozen_string_literal: true

require "test_helper"

class QuicsilverRoutesTest < Minitest::Test
  class Mapper
    include Quicsilver::Routes

    attr_reader :mounted

    def match(path, to:, via:, **options)
      @mounted = { path: path, to: to, via: via, options: options }
    end
  end

  class Endpoint
    def self.call(_env)
      [200, {}, []]
    end
  end

  def test_webtransport_mounts_rack_callable_endpoint
    mapper = Mapper.new

    mapper.webtransport "/cursors", to: Endpoint

    assert_equal({ path: "/cursors", to: Endpoint, via: :all, options: {} }, mapper.mounted)
  end

  # A class named by string is looked up per request, so a reload in development serves the new one.
  def test_an_endpoint_named_by_string_is_looked_up_when_a_request_arrives
    mapper = Mapper.new
    mapper.webtransport "/late", to: "quicsilver_routes_test/late_endpoint"
    self.class.const_set(:LateEndpoint, Class.new { def self.call(_env) = [204, {}, []] })

    assert_equal [204, {}, []], mapper.mounted[:to].call({})
  ensure
    self.class.send(:remove_const, :LateEndpoint) if self.class.const_defined?(:LateEndpoint, false)
  end

  def test_webtransport_forwards_route_options
    mapper = Mapper.new

    mapper.webtransport "/cursors", to: Endpoint, as: :cursors

    assert_equal :cursors, mapper.mounted.fetch(:options).fetch(:as)
  end
end
