# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "quicsilver-rails"

require "minitest/autorun"

# Poll until the block is truthy or the deadline passes.
#
# WebTransport endpoints run their receive loop on a spawned thread, so most
# assertions here are about state that settles shortly after #call returns.
def wait_until(timeout: 1)
  deadline = Time.now + timeout
  sleep 0.01 until yield || Time.now > deadline
end

# Length-prefixed frame, matching FramedStream's wire format. Useful for
# asserting on raw writes.
def frame(message)
  message = message.to_s.b
  [message.bytesize].pack("N") + message
end

# Shared doubles for WebTransport tests.
#
# Session and RawStream were previously redefined in every endpoint test with
# slightly different shapes, which made it easy to test against a double that
# did not behave like the real thing. One definition each, covering the whole
# surface the endpoints actually call.
module WebTransportDoubles
  # Rack env value under "quicsilver.context".
  Context = Struct.new(:webtransport, keyword_init: true)

  # Stands in for Quicsilver::WebTransport::Session.
  class Session
    attr_reader :accepted, :closed, :rejected_with, :datagrams_sent

    def initialize(*streams, open: true, datagrams: [])
      @streams = streams
      @incoming_datagrams = datagrams
      @open = open
      @accepted = false
      @closed = false
      @rejected_with = nil
      @datagrams_sent = []
      @close_callback = nil
    end

    def accept! = @accepted = true
    def accepted? = @accepted
    def open? = @open && !@closed
    def reject!(status) = @rejected_with = status

    def close
      @closed = true
      @close_callback&.call
    end

    def on_stream(&block) = @streams.each(&block)
    def on_datagram(&block) = @incoming_datagrams.each(&block)
    def send_datagram(packet) = @datagrams_sent << packet

    # Fires immediately if the session has already closed. Without this a
    # listener that registers after the peer has gone waits forever, which is
    # a real deadlock and not something a double should paper over.
    def on_close(&block)
      @close_callback = block
      block.call if @closed
    end
  end

  # Length-prefixed stream, matching FramedStream's wire format.
  class RawStream
    attr_reader :writes, :closed

    def initialize(*messages)
      @reads = Queue.new
      messages.each { |message| @reads << frame(message) }
      @reads.close
      @writes = []
      @closed = false
    end

    def read
      @reads.pop
    rescue ClosedQueueError
      nil
    end

    def write(data) = @writes << data
    def close = @closed = true

    # Decoded view of everything written, for assertions.
    def messages
      @writes.map do |frame|
        length = frame.byteslice(0, 4).unpack1("N")
        frame.byteslice(4, length)
      end
    end

    def json_messages
      messages.map { |message| JSON.parse(message) }
    end

    private
      def frame(message)
        message = message.to_s.b
        [message.bytesize].pack("N") + message
      end
  end
end
