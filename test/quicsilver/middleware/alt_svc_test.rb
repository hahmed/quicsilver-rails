# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../lib/quicsilver/middleware/alt_svc"

class QuicsilverMiddlewareAltSvcTest < Minitest::Test
  def test_adds_default_alt_svc_header
    app = ->(_env) { [200, { "content-type" => "text/plain" }, ["ok"]] }
    middleware = Quicsilver::Middleware::AltSvc.new(app)

    status, headers, body = middleware.call({})

    assert_equal 200, status
    assert_equal %(h3=":4433"; ma=86400), headers["alt-svc"]
    assert_equal ["ok"], body
  end

  def test_adds_custom_alt_svc_header
    app = ->(_env) { [204, {}, []] }
    middleware = Quicsilver::Middleware::AltSvc.new(app, port: 3000, max_age: 60)

    status, headers, body = middleware.call({})

    assert_equal 204, status
    assert_equal %(h3=":3000"; ma=60), headers["alt-svc"]
    assert_equal [], body
  end

  def test_preserves_existing_headers
    app = ->(_env) { [200, { "x-test" => "yes" }, ["ok"]] }
    middleware = Quicsilver::Middleware::AltSvc.new(app, port: 4433)

    _status, headers, _body = middleware.call({})

    assert_equal "yes", headers["x-test"]
    assert_equal %(h3=":4433"; ma=86400), headers["alt-svc"]
  end

  def test_replaces_existing_alt_svc_header
    app = ->(_env) { [200, { "alt-svc" => "clear" }, ["ok"]] }
    middleware = Quicsilver::Middleware::AltSvc.new(app, port: 3000)

    _status, headers, _body = middleware.call({})

    assert_equal %(h3=":3000"; ma=86400), headers["alt-svc"]
  end
end
