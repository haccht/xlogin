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

    def size=(val)
      @mutex.synchronize { @size = val }
    end

    def idle=(val)
      @mutex.synchronize { @idle = val }
    end

    def with
      session = deq
      begin
        session.prompt
      rescue IOError, EOFError, Errno::ECONNABORTED, Errno::ECONNREFUSED, Errno::ECONNRESET
        destroy session
        session = deq
      end

      Thread.handle_interrupt(Exception => :immediate) { yield session }
    ensure
      enq session
    end

    def close
      while @queue.empty?
        session, _, _ = @queue.deq
        destroy session
      end
    end

    private
    def deq
      @mutex.synchronize do
        if @queue.empty? && @created < @size
          @created += 1
          return Xlogin.get(@args, **@opts)
        end
      end

      session, created, cleaner = @queue.deq
      if Time.now - created < @idle
        destroy session
        return deq
      end

      cleaner.kill
      session
    end

    def enq(session)
      created = Time.now
      cleaner = Thread.new(session) do |s|
        sleep @idle * 2
        s.close rescue nil
      end

      @queue.enq [session, created, cleaner]
    end

    def destroy(session)
      @mutex.synchronize do
        session.close rescue nil
        @created -= 1
      end
    end

  end

end
