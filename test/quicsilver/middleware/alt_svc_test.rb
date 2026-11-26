# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../lib/quicsilver/middleware/alt_svc"

class QuicsilverMiddlewareAltSvcTest < Minitest::Test
  def setup
    @previous_port = ENV.delete("QUICSILVER_PORT")
  end

  def teardown
    @previous_port ? ENV["QUICSILVER_PORT"] = @previous_port : ENV.delete("QUICSILVER_PORT")
  end

  def test_advertises_the_port_the_listener_binds_by_default
    app = ->(_env) { [200, { "content-type" => "text/plain" }, ["ok"]] }
    middleware = Quicsilver::Middleware::AltSvc.new(app)

    status, headers, body = middleware.call({})

    assert_equal 200, status
    assert_equal %(h3=":3443"; ma=86400), headers["alt-svc"]
    assert_equal ["ok"], body
  end

  # Whether the engine adds the middleware, from config.quicsilver.alt_svc.
  def test_is_on_by_default_when_an_http3_listener_is_configured
    assert_nil Quicsilver::Middleware::AltSvc.options_for(nil, env: {})
    assert_equal({}, Quicsilver::Middleware::AltSvc.options_for(nil, env: { "QUICSILVER_PORT" => "3443" }))
  end

  def test_false_turns_it_off_even_with_a_listener_configured
    assert_nil Quicsilver::Middleware::AltSvc.options_for(false, env: { "QUICSILVER_PORT" => "3443" })
  end

  def test_true_or_options_turn_it_on_without_a_listener_configured
    assert_equal({}, Quicsilver::Middleware::AltSvc.options_for(true, env: {}))
    assert_equal({ max_age: 60 }, Quicsilver::Middleware::AltSvc.options_for({ max_age: 60 }, env: {}))
  end

  def test_advertises_quicsilver_port
    ENV["QUICSILVER_PORT"] = "443"
    middleware = Quicsilver::Middleware::AltSvc.new(->(_env) { [200, {}, []] })

    _status, headers, _body = middleware.call({})

    assert_equal %(h3=":443"; ma=86400), headers["alt-svc"]
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
