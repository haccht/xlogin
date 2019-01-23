require 'addressable/uri'
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

      @name     = opts[:name] || @host
      @config   = OpenStruct.new(opts)
      @template = template
      @username, @password = uri.userinfo.to_s.split(':')

      ssh_tunnel(@config.via) if @config.via
      max_retry = @config.retry || 1

      @mutex   = Mutex.new
      @loggers = [@config.log].flatten.uniq.reduce({}) { |a, e| a.merge(e => build_logger(e)) }

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
        raise e
      end
    end

    def type
      @template.name
    end

    def enable(*args)
      return super(*args) unless args.empty?
      super(@config.enable)
    end

    def prompt
      cmd('').to_s.lines.last&.chomp
    end

    def duplicate
      @template.build(@uri, **@config.to_h)
    end

    def puts(*args, &block)
      args = [instance_exec(*args, &@template.interrupt!)].flatten.compact if @template.interrupt!
      super(*args, &block) unless args.empty?
    end

    def waitfor(*args, &block)
      args = [Regexp.union(*@template.prompt.map(&:first))] if args.empty?
      @mutex.synchronize { _waitfor(*args, &block) }
    end

    def close
      @mutex.synchronize do
        @loggers.each do |_, logger|
          next if logger.nil? || [$stdout, $stderr].include?(logger)
          logger.close
        end
        @gateway.shutdown! if @gateway

        super
      end
    end

    def enable_log(log = $stdout)
      @loggers.update(log => build_logger(log))
      if block_given?
        yield
        disable_log(log)
      end
    end

    def disable_log(log = $stdout)
      @loggers.delete(log)
      if block_given?
        yield
        enable_log(log)
      end
    end

    private
    def _waitfor(*args, &block)
      __waitfor = method(:waitfor).super_method
      line = __waitfor.call(*args) do |recv|
        block.call(recv) if block
        @loggers.each { |_, logger| logger.syswrite(text) if logger }
      end

      _, process = @template.prompt.find { |r, p| r =~ line && p }
      if process
        instance_eval(&process)
        line += _waitfor(*args, &block)
      end

      return line
    end

    def ssh_tunnel(gateway)
      gateway_uri = Addressable::URI.parse(gateway)
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

    def build_logger(log)
      case log
      when String
        FileUtils.mkdir_p(File.dirname(log))
        File.open(log, 'a+').tap do |logger|
          logger.binmode
          logger.sync = true
        end
      when IO, StringIO
        log
      end
    end

  end
end
