# frozen_string_literal: true

require "rails"
require "action_dispatch"
require "quicsilver/web_transport/thread_runner"

module Quicsilver
  module WebTransport
    # Base Rack/Rails endpoint for WebTransport sessions.
    #
    # Subclasses own application-level behavior. Quicsilver core owns the raw
    # HTTP/3/WebTransport protocol; this class owns Rails admission, executor
    # wrapping, and long-lived session cleanup.
    class Endpoint
      class << self
        def call(env)
          new(env).call
        end
      end

      attr_reader :env, :session, :request

      def initialize(env)
        @env = env
        @session = Quicsilver::WebTransport.from_env(env)
        @request = build_request(env)
      end

      def call
        return not_found unless session

        connect
        session.accept!
        spawn(:session) { run }

        accepted
      rescue => error
        reject(error)
      end

      def connect
      end

      def disconnect
      end

      private

      def run
        raise NotImplementedError, "#{self.class} must implement #run"
      ensure
        disconnect
        session.close if session.open?
      end

      def wait_for_session_close
        closed = Queue.new
        session.on_close { closed.close }
        closed.pop
      rescue ClosedQueueError
        nil
      end

      def each_stream(&block)
        session.on_stream do |raw_stream|
          spawn(:stream) { block.call(raw_stream) }
        end
      end

      def each_datagram(&block)
        session.on_datagram do |packet|
          spawn(:datagram) { block.call(packet) }
        end
      end

      def spawn(kind = :task, &block)
        runner.spawn(kind, executor: executor, source: "quicsilver.webtransport.#{kind}", &block)
      end

      def runner
        if defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application
          ::Rails.application.config.quicsilver.webtransport_runner
        else
          ThreadRunner.new
        end
      end

      def executor
        if defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application
          ::Rails.application.executor
        else
          InlineExecutor
        end
      end

      def build_request(env)
        environment = if defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application
          ::Rails.application.env_config.merge(env)
        else
          env
        end

        ActionDispatch::Request.new(environment)
      end

      def accepted
        [200, {}, []]
      end

      def not_found
        [404, { "content-type" => "text/plain; charset=utf-8" }, ["WebTransport session not found"]]
      end

      def reject(error)
        session&.reject!(500) unless session&.accepted?
        raise error
      end

      InlineExecutor = Object.new.tap do |executor|
        def executor.wrap(source: nil)
          yield
        end
      end
    end
  end
end
