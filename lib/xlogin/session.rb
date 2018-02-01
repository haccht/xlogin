require 'fileutils'
require 'net/ssh/gateway'
require 'ostruct'
require 'stringio'
require 'thread'

module Xlogin
  module SessionModule

    attr_accessor :name
    attr_accessor :config

    def initialize(template, uri, **params)
      @template = template
      @scheme   = uri.scheme
      @config   = OpenStruct.new(params)

      @host = uri.host
      @name = uri.host
      @port = uri.port
      @port ||= case @scheme
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

    def cmd(*args)
      @mutex.synchronize { super(*args) }
    end

    def puts(*args, &block)
      args = instance_exec(*args, &@template.interrupt) if @template.interrupt
      super(*args, &block)
    end

    def waitfor(*args, &block)
      return waitfor(Regexp.union(*@template.prompt.map(&:first)), &block) if args.empty?

      line = super(*args) do |recvdata|
        output_log(recvdata, &block)
      end

      _, process = @template.prompt.find { |r, p| r =~ line && p }
      if process
        instance_eval(&process)
        line += waitfor(*args, &block)
      end

      line
    rescue EOFError
      @closed = true
    end

    def aging_time(time = config.timeout)
      @ageout = Time.now + time
      Thread.start do
        sleep(time)
        close if Time.now > @ageout
      end
    end

    def close
      @gateway.shutdown! if @gateway
      @output_loggers.each do |output_log, logger|
        next unless logger
        logger.close if output_log.kind_of?(String)
      end
      super
      @closed = true
    end

    def closed?
      @closed
    end

    def dup
      uri = URI::Generic.build(@scheme, [@username, @password].compact.join(':'), @host, @port)
      @template.build(uri, **config.to_h)
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

    def output_log(text, &block)
      block.call(text) if block
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
end
