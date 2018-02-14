require 'thread'

module Xlogin

  class SessionPool

    DEFAULT_SIZE = 1
    DEFAULT_IDLE = 10

    def initialize(args, **opts)
      @args = args
      @opts = opts

      @mutex   = Mutex.new
      @queue   = Queue.new
      @created = 0
    end

    def size
      case @args
      when String then @opts[:size] || DEFAULT_SIZE
      when Hash   then @args[:size] || DEFAULT_SIZE
      end
    end

    def idle
      case @args
      when String then @opts[:idle] || DEFAULT_IDLE
      when Hash   then @args[:idle] || DEFAULT_IDLE
      end
    end

    def with
      session = deq
      begin
        Thread.handle_interrupt(Exception => :immediate) { yield session }
      ensure
        enq(session)
      end
    end

    private
    def deq
      session = try_create
      unless session
        session, expires = @queue.deq
        if expires < Time.now
          session.close
          session = session.duplicate
        end
      end

      session
    end

    def enq(session)
      @queue.enq [session, Time.now + idle]
    end

    def try_create
      @mutex.synchronize do
        return unless @created < size

        @created += 1
        Xlogin.get(@args, **@opts)
      end
    end
  end
end
