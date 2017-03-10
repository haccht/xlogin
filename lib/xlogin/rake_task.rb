require 'rake'
require 'rake/tasklib'
require 'readline'
require 'thread'

module Xlogin
  class RakeTask < Rake::TaskLib

    begin
      require 'rspec/expectations'
      require 'xlogin/rspec'

      include RSpec::Matchers
    rescue LoadError
      module RSpec
        module Expectations
          class ExpectationNotMetError < StandardError; end
        end
      end
    end

    class << self
      include Rake::DSL

      def hostnames_from_file(filepath)
        hostnames = IO.readlines(filepath).map(&:strip).grep(/^\s*[^#]/)
        hostcount = hostnames.uniq.inject({}) { |a, e| a.merge(e => hostnames.count(e)) }
        dup_hosts = hostcount.keys.select { |hostname| hostcount[hostname] > 1 }
        raise Xlogin::GeneralError.new("Duplicate hosts found - #{dup_hosts.join(', ')}") unless dup_hosts.empty?

        hostnames
      end

      def default_path(&block)
        path = self.name.split('::').first.downcase
        namespace(path, &block)
      end

      def current_path
        Rake.application.current_scope.path
      end

      def synchronize(&block)
        @mutex ||= Mutex.new
        @mutex.synchronize(&block) if block
      end
    end


    attr_reader :options, :errors

    def initialize(nodename, **opts, &block)
      @errors  = []
      @session = nil
      @session_opts = opts

      @options = Rake.application.options.dup
      @options.quiet = false
      @options.fail_on_error = true

      @nodename = nodename
      @response = nil

      if RakeTask.current_path.empty?
        RakeTask.default_path { define(&block) }
      else
        define(&block)
      end
    end

    private
    def define(&block)
      lockfile = File.join('locks', "#{RakeTask.current_path}:#{@nodename}.lock")

      task(@nodename => lockfile)
      file(lockfile) do
        logfile = File.join('logs', "#{@nodename}_#{Time.now.strftime('%Y%m%d%H%M%S')}.log")
        mkdir_p(File.dirname(logfile),  verbose: @options.trace)

        loggers = [logfile, @session_opts[:log], $stdout].flatten.compact.uniq
        loggers.delete($stdout) if @options.always_multitask || @options.silent

        begin
          @session = Xlogin.get(@nodename, @session_opts.merge(log: loggers))
          instance_exec(@nodename, &block) if block
        rescue => e
          raise if @options.fail_on_error
          @errors << [@nodename, '-', e]

          message = "#{@nodename}: #{e}"
          msg_output($stderr, message)
        end

        if @errors.empty?
          mkdir_p(File.dirname(lockfile), verbose: @options.trace)
          touch(lockfile, verbose: @options.trace)
        end
      end
    end

    def method_missing(name, *args, &block)
      return super unless @session.respond_to?(name)
      @session.send(name, *args, &block)
    end

    def set(**opts)
      temp = opts.keys.inject({}) { |a, k| a[k] = @options[k]; a }
      opts.each { |k, v| @options[k] = v }
      if block_given?
        resp = yield
        temp.each { |k, v| @options[k] = v }
        resp
      end
    end

    def cmd(command = '', &block)
      return msg(command) if command =~ /^\s*#/
      return ask(command, &block) unless (Rake.verbose == false) || @options.quiet

      resp = @session.cmd(command).to_s
      if @options.always_multitask && !@options.silent
        message = resp.lines.map { |line| "[#{@session.name}] #{line}" }.join
        msg_output($stdout, message)
      end

      instance_exec(resp, &block).to_s if block
      resp
    rescue RSpec::Expectations::ExpectationNotMetError => e
      raise e if @options.fail_on_error
      @errors << [@nodename, command, e]

      message = "#{@session.name}: #{command}\n#{e}"
      msg_output($stderr, "\n")
      msg_output($stderr, message)
    end

    def msg(message)
      return if @options.silent

      if @options.always_multitask
        message = message.lines.map { |line| "[#{@session.name}] #{line}" }.join
      end

      msg_output($stdout, message)

      # prepare prompt for next command
      set(quiet: true) { cmd('') }
    end

    def ask(command = '', **opts, &block)
      prompt = set(quiet: true) { cmd('') }.lines.last
      prompt = "[#{@session.name}] #{prompt}" if @options.always_multitask

      my_command = RakeTask.synchronize do
        Readline.pre_input_hook = lambda do
            Readline.insert_text(command)
            Readline.redisplay
        end
        # clear current line and redisplay prompt
        Readline.readline("\e[E\e[K#{prompt}", false)
      end

      case my_command.strip
      when command.strip, ''
        # if my_command equals to '', it means to skip this command.
        set(quiet: true) { cmd(my_command, &block) }
      else
        set(quiet: true) { cmd(my_command) }
        ask(command, **opts, &block)
      end
    end

    def msg_output(io, *messages)
      RakeTask.synchronize do
        messages.each { |message| io.puts message }
      end
    end

    def cmd_load(file)
      content = File.exist?(file) ? IO.read(file) : ''
      instance_eval(content)
    end
  end
end
