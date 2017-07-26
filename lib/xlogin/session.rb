require 'thread'
require 'timeout'
require 'stringio'

module Xlogin
  module Session

    attr_reader   :opts
    attr_accessor :name

    def configure_session(**opts)
      @opts     = opts.dup
      @host     = @opts[:host]
      @name     = @opts[:name] || @host
      @port     = @opts[:port]
      @userinfo = @opts[:userinfo].to_s
      raise Xlogin::GeneralError.new('Argument error.') unless @host && @port

      @prompts  = @opts[:prompts] || [[/[$%#>] ?\z/n, nil]]
      @timeout  = @opts[:timeout] || 60

      @loglist  = [@opts[:log]].flatten.compact
      @logger   = update_logger

      @mutex    = Mutex.new
    end

    def waitfor(*expect)
      if expect.compact.empty?
        super(Regexp.union(*@prompts.map(&:first)), &@logger)
      else
        line = super(*expect, &@logger)
        _, process = @prompts.find { |r, p| r =~ line && p }
        if process
          instance_eval(&process)
          line += waitfor(*expect)
        end
        line
      end
    end

    def lock(timeout: @timeout)
      granted = false

      begin
        Timeout.timeout(timeout) { @mutex.lock }
        granted = true
        yield self
      ensure
        @mutex.unlock if @mutex.locked? && granted
      end
    end

    def with_retry(max_retry: 1)
      begin
        yield self
      rescue => e
        renew if respond_to?(:renew)
        raise e if (max_retry -= 1) < 0
        retry
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
