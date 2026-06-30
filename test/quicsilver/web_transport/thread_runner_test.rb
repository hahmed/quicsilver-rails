# frozen_string_literal: true

require "test_helper"

class QuicsilverWebTransportThreadRunnerTest < Minitest::Test
  class Executor
    attr_reader :source

    def wrap(source:)
      @source = source
      yield
    end
  end

  def test_spawn_runs_work_inside_executor
    runner = Quicsilver::WebTransport::ThreadRunner.new
    executor = Executor.new
    queue = Queue.new

    thread = runner.spawn(executor: executor, source: "test.source") do
      queue << :done
    end

    assert_equal :done, queue.pop
    assert_equal "test.source", executor.source
    thread.join
  end
end
