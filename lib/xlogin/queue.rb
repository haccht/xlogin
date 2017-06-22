require 'timeout'
require 'thread'

module Xlogin
  class Queue

    class << self
      def get(hostname, **args)
        @queues ||= {}
        @queues[hostname] ||= Xlogin::Queue.new(hostname, **args)
      end
    end

    def initialize(hostname, **args)
      @name = hostname
      @args = args

      @mutex = Mutex.new
      @timeout = @args[:timeout] || @args['timeout'] || @args['Timeout'] || 10
    end

    def with(timeout: @timeout, limit: 1)
      Timeout.timeout(timeout) do
        @mutex.synchronize do
          retry_count = 0

          begin
            @session ||= Xlogin.get(@name, **@args)
            @session.cmd('')
          rescue Errno::ECONNRESET => e
            raise e unless (retry_count += 1) < limit
            @session = nil
            retry
          end

          yield @session
        end
      end
    end

    def shutdown(**args)
      with(args) do |s|
        begin
          yield s ensure s.close if s
        end
      end
    end

  end
end
