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
end
