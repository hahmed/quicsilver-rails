# frozen_string_literal: true

require "test_helper"
require "action_cable"
require "localhost/authority"
require "json"
require "socket"

# Action Cable over a real QUIC connection.
#
# Every other test in this gem runs against doubles. Doubles kept answering
# notify_reset for three quicsilver releases after it was renamed, so this is
# the test that notices when the contract between the two gems moves. It
# drives exactly what app/javascript/quicsilver/action_cable.js sends: a
# WebTransport CONNECT to /cable, one bidirectional stream, length-prefixed
# Action Cable JSON on it.
class ActionCableOverWebTransportTest < Minitest::Test
  class Connection < ActionCable::Connection::Base
  end

  class EchoChannel < ActionCable::Channel::Base
    def subscribed
      stream_from "echo"
    end

    def shout(data)
      ActionCable.server.broadcast("echo", { "heard" => data["text"] })
    end
  end

  def setup
    Quicsilver::ActionCable.install!

    config = ActionCable::Server::Configuration.new
    config.cable = { "adapter" => "async" }
    config.connection_class = -> { Connection }
    config.disable_request_forgery_protection = true
    config.logger = Logger.new(File::NULL)
    @cable = ActionCable::Server::Base.new(config: config)
    # EchoChannel#shout broadcasts through the global server.
    ActionCable.instance_variable_set(:@server, @cable)

    @port = free_port
    authority = Localhost::Authority.fetch
    quic = Quicsilver::Transport::Configuration.new(authority.certificate_path, authority.key_path)
    @server = Quicsilver::Server.new(@port, address: "127.0.0.1", app: @cable, server_configuration: quic)
    Quicsilver::Server.instance = @server
    @thread = Thread.new { @server.start }
    wait_until(timeout: 5) { @server.running? }
    Quicsilver.logger = Logger.new(File::NULL)
  end

  def teardown
    @client&.disconnect
    @server&.stop
    @thread&.join(3)
  end

  def test_subscribe_and_broadcast_round_trip_over_a_bidi_stream
    @client = CableClient.new(@port)
    @client.connect_cable("/cable")

    assert_equal "welcome", @client.read_json["type"]

    identifier = { channel: EchoChannel.name }.to_json
    @client.send_json(command: "subscribe", identifier: identifier)
    confirmation = @client.read_json_until { |m| m["type"] == "confirm_subscription" }
    assert_equal identifier, confirmation["identifier"]

    @client.send_json(command: "message", identifier: identifier, data: { action: "shout", text: "over quic" }.to_json)
    message = @client.read_json_until { |m| m["message"] }
    assert_equal({ "heard" => "over quic" }, message["message"])
    assert_equal identifier, message["identifier"]
  end

  def test_a_request_that_is_not_webtransport_is_not_a_cable_socket
    client = Quicsilver::Client.new("127.0.0.1", @port, unsecure: true, request_timeout: 3)
    response = client.get("/cable")
    assert_equal 404, response.status
  ensure
    client&.disconnect
  end

  private

  def free_port
    socket = UDPSocket.new(Socket::AF_INET6)
    socket.setsockopt(:IPV6, :V6ONLY, 0)
    socket.bind("::", 0)
    socket.addr[1]
  ensure
    socket&.close
  end

  # The browser side of action_cable.js, in Ruby: one QUIC connection, a
  # WebTransport CONNECT, one bidi stream, [length][json] frames.
  class CableClient < Quicsilver::Client
    WT_STREAM_BIDI = 0x41

    def initialize(port)
      super("127.0.0.1", port, unsecure: true, request_timeout: 5)
      @events = Queue.new
      @buffer = "".b
    end

    def handle_stream_event(stream_id, event, data, early_data)
      @events << [stream_id, event, data]
      super
    end

    def connect_cable(path)
      get("/") # settle the connection and SETTINGS
      connect = open_stream
      headers = Quicsilver::Protocol.build_headers_frame([
        [":method", "CONNECT"], [":protocol", "webtransport-h3"],
        [":scheme", "https"], [":authority", "127.0.0.1"], [":path", path],
        ["origin", "https://127.0.0.1"]
      ])
      connect.send(headers)
      @session_stream_id = wait_for_stream_id(connect)
      await(connect_response_on: @session_stream_id)

      @stream = open_stream
      @stream.send(Quicsilver::Protocol.encode_varint(WT_STREAM_BIDI) +
                   Quicsilver::Protocol.encode_varint(@session_stream_id))
      @stream_id = wait_for_stream_id(@stream)
    end

    def send_json(hash)
      payload = hash.to_json.b
      @stream.send([payload.bytesize].pack("N") + payload)
    end

    def read_json(timeout: 5)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        if @buffer.bytesize >= 4
          length = @buffer.unpack1("N")
          if @buffer.bytesize >= 4 + length
            frame = @buffer.byteslice(4, length)
            @buffer = @buffer.byteslice(4 + length..) || "".b
            return JSON.parse(frame)
          end
        end
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise "timed out waiting for a cable frame" unless remaining.positive?

        sid, event, data = @events.pop(timeout: remaining)
        raise "timed out waiting for a cable frame" if event.nil?
        next unless sid == @stream_id && %w[RECEIVE RECEIVE_FIN].include?(event)

        @buffer << Quicsilver::Transport::StreamEvent.new(data, event).data
      end
    end

    def read_json_until(timeout: 5)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        message = read_json(timeout: remaining)
        return message if yield(message)
      end
    end

    private

    def wait_for_stream_id(stream)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        id = stream.stream_id
        return id if id
        sleep 0.01
      end
      raise "stream never started"
    end

    # The 200 to the CONNECT arrives as RECEIVE on the session stream. Events
    # for other streams that arrive meanwhile (the cable welcome can beat it)
    # are kept, not dropped.
    def await(connect_response_on:)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      kept = []
      begin
        loop do
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise "CONNECT was not answered" unless remaining.positive?
          sid, event, data = @events.pop(timeout: remaining)
          raise "CONNECT was not answered" if event.nil?
          unless sid == connect_response_on
            kept << [sid, event, data]
            next
          end

          raise "CONNECT reset" if event == "STREAM_RESET"
          next unless event == "RECEIVE" || event == "RECEIVE_FIN"

          parser = Quicsilver::Protocol::ResponseParser.new(Quicsilver::Transport::StreamEvent.new(data, event).data)
          parser.parse
          raise "CONNECT answered #{parser.status}" unless parser.status == 200
          return
        end
      ensure
        kept.each { |e| @events << e }
      end
    end
  end
end
