# frozen_string_literal: true

require "test_helper"

class QuicsilverWebTransportFramedStreamTest < Minitest::Test
  class Stream
    attr_reader :writes

    def initialize(*reads)
      @reads = Queue.new
      reads.each { |read| @reads << read }
      @reads.close
      @writes = []
    end

    def read
      @reads.pop
    end

    def write(data)
      @writes << data
    end

    def close
      @reads.close unless @reads.closed?
    end
  end

  def test_reads_complete_message
    stream = Stream.new([5].pack("N") + "hello")
    framed = Quicsilver::WebTransport::FramedStream.new(stream)

    assert_equal "hello", framed.read_message
  end

  def test_reads_message_split_across_chunks
    stream = Stream.new([5].pack("N").byteslice(0, 2), [5].pack("N").byteslice(2, 2) + "he", "llo")
    framed = Quicsilver::WebTransport::FramedStream.new(stream)

    assert_equal "hello", framed.read_message
  end

  def test_reads_multiple_messages_from_one_chunk
    stream = Stream.new([3].pack("N") + "one" + [3].pack("N") + "two")
    framed = Quicsilver::WebTransport::FramedStream.new(stream)

    assert_equal "one", framed.read_message
    assert_equal "two", framed.read_message
  end

  def test_returns_nil_when_stream_closes_without_message
    stream = Stream.new
    framed = Quicsilver::WebTransport::FramedStream.new(stream)

    assert_nil framed.read_message
  end

  def test_write_message_frames_payload
    stream = Stream.new
    framed = Quicsilver::WebTransport::FramedStream.new(stream)

    framed.write_message("hello")

    assert_equal [[5].pack("N") + "hello"], stream.writes
  end
  # A transport double for the two tests that drive a real WebTransportStream.
  # Backpressure is on by default and grants receive credit on the native
  # stream at construction, so a nil transport no longer works.
  class NativeStream
    def grant_receive_credit(*) = true
    def send(*) = true
    def stop_sending(*) = true
    def abort(*) = true
    def handle = 0
  end

  def core_stream
    Quicsilver::Server::WebTransportStream.new(
      session: nil, stream: NativeStream.new, stream_id: 4,
      **Quicsilver::Server::WebTransportSession::DEFAULT_RECEIVE_OPTIONS
    )
  end

  def test_core_stream_preserves_fragmented_messages_through_fin_and_shutdown
    raw = core_stream
    payload = [5].pack("N") + "hello"
    raw.receive_data(payload.byteslice(0, 2))
    raw.receive_data(payload.byteslice(2..))
    raw.notify_read_close
    raw.notify_close
    framed = Quicsilver::WebTransport::FramedStream.new(raw)

    assert_equal "hello", framed.read_message
    assert_nil framed.read_message
  end

  def test_core_stream_reset_propagates_to_message_reader
    raw = core_stream
    framed = Quicsilver::WebTransport::FramedStream.new(raw)
    raw.notify_peer_reset(Quicsilver::Protocol::WebTransport.application_error_to_http(42))

    error = assert_raises(Quicsilver::Server::WebTransportStream::ResetError) { framed.read_message }
    assert_equal 42, error.application_error_code
  end

end
