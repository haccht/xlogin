require 'fileutils'
require 'stringio'
require 'thread'

module Xlogin
  module SessionModule

    attr_reader   :config
    attr_accessor :name

    def initialize(template, uri, **opts)
      @uri  = uri
      @host = uri.host
      @port = uri.port
      @port ||= case @uri.scheme
                when 'ssh'    then 22
                when 'telnet' then 23
                end

      @name     = opts[:name] || @host
      @tunnel   = opts[:tunnel] || opts[:via]
      @config   = ReadOnlyStruct.new(opts)
      @template = template
      @loggers  = [@config.log].flatten.uniq.reduce({}){ |a, e| a.merge(e => build_log(e)) }
      @host, @port = Xlogin.factory.open_tunnel(@tunnel, @host, @port) if @tunnel

      num_try = 0
      username, password = uri.userinfo.to_s.split(':')

      begin
        args = Hash.new
        args['Timeout'] = @config.timeout || @template.timeout || false
        args['Prompt' ] = prompt_pattern
        args['FailEOF'] = true
        if @config.proxy
          args['Proxy'   ] = @config.proxy
        else
          args['Host'    ] = @host
          args['Port'    ] = @port
          args['Username'] = username
          args['Password'] = password
        end

        super(args)
      rescue => e
        unless (num_try += 1) > (@config.retry || 0)
          sleep 2.0 ** (num_try)
          retry
        end
        raise e
      end
    end

    def type
      @template.name
    end

    def prompt
      text = cmd('').to_s.lines.last
      text.chomp if text
    end

    def prompt_pattern
      Regexp.union(*@template.prompts.map(&:first))
    end

    def duplicate(type: @template.name, **args)
      template = Xlogin::Factory.instance.get_template(type)
      raise Xlogin::Error.new("Template not found: '#{type}'") unless template

      template.build(@uri, **@config.to_h.merge(args))
    end

    def puts(string = '', &block)
      super(string, &block)
    end

    def print(string = '', &block)
      string = instance_exec(string, &@template.interrupt!) if @template.interrupt!
      super(string, &block)
    end

    def waitfor(*args, &block)
      return waitfor(prompt_pattern) if args.empty?

      line = super(*args) do |recv|
        log_message(recv)
        block.call(recv) if block
      end

      _, process = @template.prompts.find{ |r, p| r =~ line && p }
      if process
        instance_eval(&process)
        line += waitfor(*args, &block)
      end

      return line
    end

    def close
      @loggers.each do |_, logger|
        next if [$stdout, $stderr, nil].include?(logger)
        logger.close
      end

      Xlogin.factory.close_tunnel(@tunnel, @port) if @tunnel
      super
    end

    def enable_log(log = $stdout)
      @loggers.update(log => build_log(log))
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

    def log_message(text)
      @loggers.each{ |_, logger| logger.syswrite(text) if logger }
    end

    private
    def build_log(log)
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
