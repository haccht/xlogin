require 'connection_pool'
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
      @template = template
      @config   = OpenStruct.new(opts)

      @uri  = uri
      @host = uri.host
      @name = uri.host
      @port = uri.port
      @port ||= case @uri.scheme
                when 'ssh'    then 22
                when 'telnet' then 23
                end

      @username, @password = uri.userinfo.to_s.split(':')
      raise ArgumentError.new("Invalid URI - '#{uri}'") unless @host && @port

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
      line = ''
      return waitfor(Regexp.union(*@template.prompt.map(&:first)), &block) if args.empty?

      line = super(*args, &block)

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
          logger = File.open(output_log, 'a+')
          logger.binmode
          logger.sync = true

          loggers[output_log] = logger
        when IO, StringIO
          loggers[output_log] = output_log
        end
      end
    end
  end

  class SessionPool

    def initialize(args, **opts)
      temp = case args
             when String then opts.select { |k, v| %i(size timeout).member?(k) && !v.nil? }
             when Hash   then args.select { |k, v| %i(size timeout).member?(k) && !v.nil? }
             end

      @pool = ConnectionPool.new(**temp) { Wrapper.new(args, **opts) }
    end

    def with(**opts)
      @pool.with(**opts) do |session|
        session.repair if session.closed?
        session.aging_time(opts[:aging]) if opts[:aging]

        yield session
      end
    end

    class Wrapper
      def initialize(*args)
        @session = Xlogin.get(*args)
        @agetime = nil
      end

      def repair
        @session = @session.duplicate
      end

      def aging_time(time = @session.config.timeout)
        @agetime = Time.now + time
        Thread.start do
          sleep(time)
          @session.close if Time.now > @agetime
        end
      end

      def method_missing(name, *args, &block)
        @session.send(name, *args, &block)
      end
    end

  end
end
