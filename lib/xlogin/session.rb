require 'stringio'

module Xlogin
  module Session

    attr_reader   :opts
    attr_accessor :name

    def configure_session(**opts)
      @opts     = opts.dup
      @host     = @name = @opts[:host]
      @port     = @opts[:port]
      @userinfo = @opts[:userinfo].to_s.split(':')
      raise Xlogin::GeneralError.new('Argument error.') unless @host && @port

      @prompts  = @opts[:prompts] || [[/[$%#>] ?\z/n, nil]]
      @timeout  = @opts[:timeout] || 60

      @loglist  = [@opts[:log]].flatten.compact
      @logger   = update_logger
    end

    def thread_safe(timeout: @timeout, maximum_retry: 1)
      @safe_session = self
      @safe_session_mutex ||= Mutex.new

      Timeout.timeout(timeout) do
        @safe_session_mutex.synchronize do
          retry_count = 0
          begin
            @safe_session ||= Xlogin.get(@host, @opts)
            yield @safe_session
          rescue Errno::ECONNRESET => e
            raise e unless (retry_count += 1) < maximum_retry
            @safe_session = nil
            retry
          end
        end
      end
    end

    def enable_log(out = $stdout)
      enabled = @loglist.include?(out)
      unless enabled
        @loglist.push(out)
        update_logger
      end

      if block_given?
        yield
        disable_log(out) unless enabled
      end
    end

    def disable_log(out = $stdout)
      enabled = @loglist.include?(out)
      if enabled
        @loglist.delete(out)
        update_logger
      end

      if block_given?
        yield
        enable_log(out) if enabled
      end
    end

    private
    def update_logger
      loglist = [@loglist].flatten.uniq.map do |log|
        case log
        when String
          log = File.open(log, 'a+')
          log.binmode
          log.sync = true
          log
        when IO, StringIO
          log
        end
      end

      @logger = lambda { |c| loglist.compact.each { |o| o.syswrite c } }
    end
  end
end
