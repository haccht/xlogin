require 'thread'

module Xlogin

  class SessionPool

    DEFAULT_POOL_SIZE = 1

    def initialize(args, **opts)
      @args = args
      @opts = opts
      @size = case @args
              when String then @opts.delete(:pool_size) || DEFAULT_POOL_SIZE
              when Hash   then @args.delete(:pool_size) || DEFAULT_POOL_SIZE
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
        session.close rescue nil
        @created -= 1
        session = try_create
      end

      Thread.handle_interrupt(Exception => :immediate) { yield session }
    ensure
      enq session
    end

    private
    def deq
      session = try_create
      session = @queue.deq unless session
      session
    end

    def enq(session)
      @queue.enq session
    end

    def try_create
      @mutex.synchronize do
        return unless @created < @size

        @created += 1
        Xlogin.get(@args, **@opts)
      end
    end

  end

end
