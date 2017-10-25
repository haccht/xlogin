require 'fileutils'
require 'net/ssh/gateway'
require 'ostruct'
require 'stringio'

module Xlogin
  module SessionModule

    attr_accessor :name
    attr_accessor :opts

    def initialize(template, uri, **params)
      @template = template
      @scheme   = uri.scheme
      @opts     = OpenStruct.new(params)

      @host = uri.host
      @name = uri.host
      @port = uri.port
      @port ||= case @scheme
                when 'ssh'    then 22
                when 'telnet' then 23
                end

      @username, @password = uri.userinfo.to_s.split(':')
      raise ArgumentError.new('Device hostname or port not specified.') unless @host && @port

      @output_logs = opts.log
      @output_loggers = prebuild_loggers

      ssh_tunnel(opts.via) if opts.via
      max_retry = opts.retry || 1

      begin
        return super(
          'Host'     => @host,
          'Port'     => @port,
          'Username' => @username,
          'Password' => @password,
          'Timeout'  => @template.timeout,
          'Prompt'   => Regexp.union(*@template.prompt.map(&:first)),
        )
      rescue => e
        retry if (max_retry -= 1) > 0
        raise e
      end
    end

    def prompt
      cmd('').lines.last.chomp
    end

    def puts(line)
      line = instance_exec(line, &@template.interrupt) if @template.interrupt
      super(line)
    end

    def method_missing(name, *args, &block)
      process = @template.methods[name]
      super unless process

      instance_exec(*args, &process)
    end

    def respond_to_missing?(name, _)
      @template.methods[name]
    end

    def waitfor(*expect, &block)
      return waitfor(Regexp.union(*@template.prompt.map(&:first)), &block) if expect.empty?

      line = super(*expect) do |recvdata|
        output(recvdata, &block)
      end

      _, process = @template.prompt.find { |r, p| r =~ line && p }
      if process
        instance_eval(&process)
        line += waitfor(*expect, &block)
      end

      line
    end

    def close
      @gateway.shutdown! if @gateway
      super
    end

    def dup
      uri = URI::Generic.build(@scheme, [@username, @password].compact.join(':'), @host, @port)
      self.class.new(@template, uri, **opts.to_h)
    end

    def enable_log(out = $stdout)
      @output_loggers = prebuild_loggers(@output_logs + [out])
      if block_given?
        yield
        @output_loggers = prebuild_loggers
      end
    end

    def disable_log(out = $stdout)
      @output_loggers = prebuild_loggers(@output_logs - [out])
      if block_given?
        yield
        @output_loggers = prebuild_loggers
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

    def output(text, &block)
      [*@output_loggers, block].compact.each { |logger| logger.call(text) }
    end

    def prebuild_loggers(output_logs = @output_logs)
      [output_logs].flatten.compact.uniq.map do |output_log|
        logger = case output_log
                 when String
                   FileUtils.mkdir_p(File.dirname(output_log))
                   File.open(output_log, 'a+').tap do |file|
                     file.binmode
                     file.sync = true
                   end
                 when IO, StringIO
                   output_log
                 end

        lambda { |c| logger.syswrite c if logger }
      end
    end

  end
end
