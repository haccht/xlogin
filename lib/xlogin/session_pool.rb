require 'thread'

module Xlogin

  class SessionPool

    DEFAULT_SIZE = 1
    DEFAULT_IDLE = false

    def initialize(args, **opts)
      @args  = args
      @opts  = opts

      @mutex = Mutex.new
      @queue = Queue.new

      @created  = 0
      @watchdog = Hash.new
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
        session, updated = @queue.deq
        session = session.duplicate if idle && updated + idle.to_f < Time.now
      end

      session
    end

    def enq(session)
      @mutex.synchronize { update_watchdog(session) }
      @queue.enq [session, Time.now]
    end

    def try_create
      @mutex.synchronize do
        return unless @created < size

        session = Xlogin.get(@args, **@opts)
        update_watchdog(session)

        @created += 1
        session
      end
    end

    def update_watchdog(session)
      return unless idle

      @watchdog[session].tap { |th| th.kill if th }
      @watchdog[session] = Thread.new(session) { |s| sleep(idle.to_f + 1) && s.close }
    end
  end

end
