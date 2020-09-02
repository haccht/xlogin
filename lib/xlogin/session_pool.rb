require 'time'
require 'thread'

module Xlogin
  class SessionPool

    DEFAULT_POOL_SIZE = 1
    DEFAULT_POOL_IDLE = 60

    attr_accessor :size, :idle

    def initialize(args, **opts)
      @args = args
      @opts = opts

      @size = DEFAULT_POOL_SIZE
      @idle = DEFAULT_POOL_IDLE

      @mutex = Mutex.new
      @queue = Queue.new
      @count = 0
    end

    def with
      session = deq
      Thread.handle_interrupt(Exception => :immediate){ yield session }
    ensure
      enq session
    end

    def close
      until @queue.empty?
        session, _, _ = @queue.deq
        destroy(session)
      end
    end

    def deq
      @mutex.synchronize do
        if @queue.empty? && @count < @size
          @count += 1
          return Xlogin.get(@args, **@opts)
        end
      end

      session, last_used, watch_dog = @queue.deq

      watch_dog.kill
      if Time.now - last_used > @idle
        destroy(session)
        return deq
      end

      begin
        raise IOError if session&.sock&.closed?
        return session
      rescue IOError, EOFError, Errno::ECONNABORTED, Errno::ECONNREFUSED, Errno::ECONNRESET
        destroy(session)
        return deq
      end
    end

    def enq(session)
      last_used = Time.now
      watch_dog = Thread.new(session){ |s| sleep(@idle * 1.5) && s.close rescue nil }
      @queue.enq [session, last_used, watch_dog]
    end

    private
    def destroy(session)
      @mutex.synchronize do
        session.close rescue nil
        @count -= 1
      end
    end

  end
end
