require 'time'
require 'thread'

module Xlogin
  class SessionPool

    DEFAULT_POOL_SIZE = 1
    DEFAULT_POOL_IDLE = 60

    attr_reader :size, :idle

    def initialize(args, **opts)
      @args = args
      @opts = opts

      @size = DEFAULT_POOL_SIZE
      @idle = DEFAULT_POOL_IDLE

      @mutex = Mutex.new
      @queue = Queue.new
      @created  = 0
    end

    def size=(val)
      @mutex.synchronize { @size = val }
    end

    def idle=(val)
      @mutex.synchronize { @idle = val }
    end

    def with
      session = deq
      Thread.handle_interrupt(Exception => :immediate) { yield session }
    ensure
      enq session
    end

    def close
      while @queue.empty?
        session, _, _ = @queue.deq
        destroy(session)
      end
    end

    def deq
      @mutex.synchronize do
        if @queue.empty? && @created < @size
          @created += 1
          return Xlogin.get(@args, **@opts)
        end
      end

      session, last_used = @queue.deq
      if Time.now - last_used > @idle
        destroy(session)
        return deq
      end

      begin
        raise IOError if session.sock.closed?
      rescue IOError, EOFError, Errno::ECONNABORTED, Errno::ECONNREFUSED, Errno::ECONNRESET
        destroy(session)
        session = deq
      end

      session
    end

    def enq(session)
      last_used = Time.now
      @queue.enq [session, last_used]
    end

    def destroy(session)
      @mutex.synchronize do
        session.close rescue nil
        @created -= 1
      end
    end

  end
end
