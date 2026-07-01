# frozen_string_literal: true

module Quicsilver
  module WebTransport
    module_function

    def from_env(env)
      env["quicsilver.context"]&.webtransport || env["quicsilver.webtransport"]
    end
  end
end

require "quicsilver/web_transport/framed_stream"
require "quicsilver/web_transport/thread_runner"
require "quicsilver/web_transport/endpoint"
require "quicsilver/web_transport/datagram_endpoint"
require "quicsilver/web_transport/rpc_endpoint"
require "quicsilver/web_transport/server_streaming_endpoint"
require "quicsilver/web_transport/message_stream_endpoint"
