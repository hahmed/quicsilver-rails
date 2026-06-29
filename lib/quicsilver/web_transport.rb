# frozen_string_literal: true

module Quicsilver
  module WebTransport
    module_function

    def from_env(env)
      env["quicsilver.context"]&.webtransport || env["quicsilver.webtransport"]
    end
  end
end
