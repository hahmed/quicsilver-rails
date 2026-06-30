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

  def test_webtransport_forwards_route_options
    mapper = Mapper.new

    mapper.webtransport "/cursors", to: Endpoint, as: :cursors

    assert_equal :cursors, mapper.mounted.fetch(:options).fetch(:as)
  end
end
