# frozen_string_literal: true

module Quicsilver
  module WebTransport
    # Default runner for long-lived WebTransport endpoint work.
    #
    # The runner owns the concurrency choice for endpoint receive loops. The
    # default is deliberately boring: one Ruby thread per accepted WebTransport
    # endpoint, with the work wrapped in the Rails executor when available.
    class ThreadRunner
      def spawn(kind = :task, executor:, source:, &block)
        Thread.new do
          executor.wrap(source: source, &block)
        end
      end
    end
  end
end
