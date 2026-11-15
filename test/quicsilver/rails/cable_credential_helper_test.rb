# frozen_string_literal: true

require "test_helper"
require "action_view"

class CableCredentialHelperTest < Minitest::Test
  class View
    include ActionView::Helpers::TagHelper
    include Quicsilver::Rails::CableCredentialHelper
  end

  def with_alt_svc(value)
    config = ActiveSupport::OrderedOptions.new
    config.quicsilver = ActiveSupport::OrderedOptions.new
    config.quicsilver.alt_svc = value
    app = Struct.new(:config).new(config)
    ::Rails.stub(:application, app) { yield }
  end

  def test_renders_when_http3_is_advertised
    with_alt_svc(true) do
      assert_includes View.new.quicsilver_cable_credential_meta_tag("abc"), %(content="abc")
    end
  end

  def test_renders_nothing_without_http3
    with_alt_svc(nil) { assert_nil View.new.quicsilver_cable_credential_meta_tag("abc") }
  end

  def test_renders_nothing_without_a_credential
    with_alt_svc(true) { assert_nil View.new.quicsilver_cable_credential_meta_tag(nil) }
  end
end
