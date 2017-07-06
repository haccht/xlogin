require 'timeout'
require 'thread'

module Xlogin
  class Queue
    class << self
      def login_opts(**opts)
        @login_opts = opts unless opts.empty?
        @login_opts || {}
      end

      def get(hostname)
        @queues ||= {}
        @queues[hostname] ||= Xlogin::Queue.new(hostname, **login_opts)
      end
    end

    def initialize(hostname, **args)
      @name    = hostname
      @args    = args
      @mutex   = Mutex.new
      @session = nil

      if hostinfo = Xlogin.factory.get(hostname)
        firmware = Xlogin.factory.template_for(hostinfo[:type])
        @timeout = firmware.instance_exec{ @timeout }
      end

      @timeout = @args['Timeout'] || @args['timeout' || @args[:timeout]] || @timeout || 10
    end

    def raw_session
      @session
    end

    def with(timeout: @timeout, limit: 1)
      @mutex.synchronize do
        @session ||= Xlogin.get(@name, **@args)
      end

      Timeout.timeout(timeout) do
        @mutex.synchronize do
          retry_count = 0
          begin
            yield @session
          rescue Errno::ECONNRESET => e
            raise e unless (retry_count += 1) < limit
            @session = nil
            retry
          end
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
