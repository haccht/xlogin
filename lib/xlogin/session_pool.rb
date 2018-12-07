require 'thread'

module Xlogin

  class SessionPool

    DEFAULT_POOL_SIZE = 1
    DEFAULT_POOL_IDLE = 60

    def initialize(args, **opts)
      @args = args
      @opts = opts

      case @args
      when String
        @size = @opts.delete(:pool_size) || DEFAULT_POOL_SIZE
        @idle = @opts.delete(:pool_idle) || DEFAULT_POOL_IDLE
      when Hash
        @size = @args.delete(:pool_size) || DEFAULT_POOL_SIZE
        @idle = @args.delete(:pool_idle) || DEFAULT_POOL_IDLE
      end

      @mutex = Mutex.new
      @queue = Queue.new
      @created  = 0
    end

    def with
      session = deq

      begin
        session.prompt
      rescue IOError, EOFError, Errno::ECONNABORTED, Errno::ECONNREFUSED, Errno::ECONNRESET
        destroy(session)
        session = try_create
      end

      Thread.handle_interrupt(Exception => :immediate) { yield session }
    ensure
      enq session
    end

    def close
      while @queue.empty?
        session, _ = @queue.deq
        destroy(session)
      end
    end

    private
    def deq
      unless session = try_create
        session, timer = @queue.deq
        timer.kill
      end
      session
    end

    def enq(session)
      timer = Thread.new do
        sleep @idle * 1.2
        destroy(session)
      end

      @queue.enq [session, timer]
    end

    def try_create
      @mutex.synchronize do
        return unless @created < @size

        @created += 1
        Xlogin.get(@args, **@opts)
      end
    end

    def destroy(session)
      @mutex.synchronize do
        session.close rescue nil
        @created -= 1
      end
    end

  end

end
