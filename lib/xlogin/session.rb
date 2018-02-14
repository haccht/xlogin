require 'delegate'
require 'fileutils'
require 'net/ssh/gateway'
require 'ostruct'
require 'stringio'
require 'thread'

module Xlogin
  module SessionModule

    attr_accessor :name
    attr_accessor :config

    def initialize(template, uri, **opts)
      @uri  = uri
      @host = uri.host
      @port = uri.port
      @port ||= case @uri.scheme
                when 'ssh'    then 22
                when 'telnet' then 23
                end

      raise ArgumentError.new("Invalid URI - '#{uri}'") unless @host && @port

      @name     = opts.delete(:name) || @host
      @config   = OpenStruct.new(opts)
      @template = template
      @username, @password = uri.userinfo.to_s.split(':')

      ssh_tunnel(@config.via) if @config.via
      max_retry = @config.retry || 1

      @mutex  = Mutex.new
      @closed = false
      @output_logs    = [@config.log]
      @output_loggers = build_loggers

      begin
        super(
          'Host'     => @host,
          'Port'     => @port,
          'Username' => @username,
          'Password' => @password,
          'Timeout'  => @config.timeout || @template.timeout || false,
          'Prompt'   => Regexp.union(*@template.prompt.map(&:first)),
          'FailEOF'  => true,
        )
      rescue => e
        retry if (max_retry -= 1) > 0
        @closed = true
        raise e
      end
    end

    def type
      @template.name
    end

    def prompt
      cmd('').lines.last.chomp
    end

    def cmd(*args, &block)
      @mutex.synchronize { super(*args, &block) }
    end

    def puts(*args, &block)
      args = instance_exec(*args, &@template.interrupt) if @template.interrupt
      super(*args, &block)
    end

    def waitfor(*args, &block)
      args << Regexp.union(*@template.prompt.map(&:first)) if args.empty?
      line = super(*args) do |recv|
        block.call(recv) if block
        output_log(recv)
      end

      _, process = @template.prompt.find { |r, p| r =~ line && p }
      if process
        instance_eval(&process)
        line += waitfor(*args, &block)
      end
    rescue EOFError
      @closed = true
    ensure
      return line
    end

    def close
      @mutex.synchronize do
        @output_loggers.each do |output_log, logger|
          next unless logger
          logger.close if output_log.kind_of?(String)
        end
        @gateway.shutdown! if @gateway

        super
        @closed = true
      end
    end

    def closed?
      @closed
    end

    def duplicate
      @template.build(@uri, **config.to_h)
    end

    def enable_log(out = $stdout)
      @output_loggers = build_loggers(@output_logs + [out])
      if block_given?
        yield
        @output_loggers = build_loggers
      end
    end

    def disable_log(out = $stdout)
      @output_loggers = build_loggers(@output_logs - [out])
      if block_given?
        yield
        @output_loggers = build_loggers
      end
    end

    private
    def ssh_tunnel(gateway)
      gateway_uri = URI(gateway)
      case gateway_uri.scheme
      when 'ssh'
        username, password = *gateway_uri.userinfo.split(':')
        @gateway = Net::SSH::Gateway.new(
          gateway_uri.host,
          username,
          password: password,
          port: gateway_uri.port || 22
        )

        @port = @gateway.open(@host, @port)
        @host = '127.0.0.1'
      end
    end

    def output_log(text)
      @output_loggers.each do |_, logger|
        next unless logger
        logger.syswrite(text)
      end
    end

    def build_loggers(output_logs = @output_logs)
      [output_logs].flatten.uniq.each.with_object({}) do |output_log, loggers|
        case output_log
        when String
          FileUtils.mkdir_p(File.dirname(output_log))
          loggers[output_log] = File.open(output_log, 'a+').tap do |logger|
            logger.binmode
            logger.sync = true
          end
        when IO, StringIO
          loggers[output_log] = output_log
        end
      end
    end
  end
end
