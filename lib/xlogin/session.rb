require 'stringio'

module Xlogin
  module Session

    attr_reader   :opts
    attr_accessor :name

    def configure_session(**opts)
      @opts     = opts.dup
      @host     = @name = @opts.delete(:host)
      @port     = @opts.delete(:port)
      @userinfo = @opts.delete(:userinfo).to_s.split(':')
      raise Xlogin::GeneralError.new('Argument error.') unless @host && @port

      @prompts  = @opts.delete(:prompts) || [[/[$%#>] ?\z/n, nil]]
      @timeout  = @opts.delete(:timeout) || 60

      @loglist  = [@opts.delete(:log)].flatten.compact
      @logger   = update_logger
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
