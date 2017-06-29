require 'rake'
require 'rake/tasklib'
require 'readline'
require 'thread'

module Xlogin
  class RakeTask < Rake::TaskLib

    class << self
      include Rake::DSL

      def bulk(names, **xlogin_opts, &block)
        names = names.map(&:strip).grep(/^\s*[^#]/)

        namecount = names.uniq.inject({}) { |a, e| a.merge(e => names.count(e)) }
        duplicate = namecount.keys.select { |name| namecount[name] > 1 }
        raise Xlogin::GeneralError.new("Duplicate hosts found - #{duplicate.join(', ')}") unless duplicate.empty?

        current_namespace do
          description = Rake.application.last_description || "Run '#{RakeTask.current_namespace}'"

          names.each do |name|
            desc "#{description} (#{name})"
            RakeTask.new(name, **xlogin_opts, &block)
          end
        end
      end

      def mutex
        @mutex ||= Mutex.new
      end

      def current_namespace
        path = Rake.application.current_scope.path

        if path.empty?
          path = self.name.split('::').first.downcase
          namespace(path) { yield } if block_given?
        else
          yield if block_given?
        end

        path
      end
    end


    attr_reader   :name
    attr_accessor :fail_on_error
    attr_accessor :silent
    attr_accessor :lockfile
    attr_accessor :logfile
    attr_accessor :uncomment

    def initialize(name, **xlogin_opts)
      @name          = name
      @fail_on_error = true
      @silent        = Rake.application.options.silent
      @lockfile      = nil
      @logfile       = nil
      @uncomment     = false
      @xlogin_opts   = xlogin_opts

      @session       = nil
      @taskrunner    = nil

      yield(self) if block_given?
      define
    end

    def start(&block)
      @taskrunner = block
    end

    def safe_puts(*messages, **opts)
      opts[:io] ||= $stdout
      return if @silent && !opts[:force]
      RakeTask.mutex.synchronize do
        messages.flat_map { |message| message.to_s.lines }.each do |line|
          line.gsub!("\r", "")
          opts[:io].puts (Rake.application.options.always_multitask)? "#{name}\t#{line}" : line
        end
      end
    end

    private
    def define
      RakeTask.current_namespace do
        description = Rake.application.last_description || "Run '#{RakeTask.current_namespace}'"

        desc description
        Rake.application.last_description = nil if uncomment

        if lockfile
          task(name => lockfile)
          file(lockfile) do
            run_task

            mkdir_p(File.dirname(lockfile), verbose: Rake.application.options.trace)
            touch(lockfile, verbose: Rake.application.options.trace)
          end
        else
          task(name) do
            run_task
          end
        end
      end
    end

    def run_task
      loggers = []
      loggers << $stdout unless silent || Rake.application.options.always_multitask

      if logfile
        mkdir_p(File.dirname(logfile), verbose: Rake.application.options.trace)
        loggers << logfile if logfile
      end

      @xlogin_opts[:log] = loggers unless loggers.empty?

      begin
        @session = Xlogin.get(name, @xlogin_opts.dup)
        @session.extend(SessionExt)

        method_proc = method(:safe_puts)
        @session.define_singleton_method(:safe_puts) { |*args| method_proc.call(*args) }

        @taskrunner.call(@session) if @taskrunner && @session
      rescue => e
        raise e if fail_on_error
        safe_puts(e, io: $stderr, force: true)
      end
    end

    module SessionExt
      def cmd(*args)
        message = super(*args)
        safe_puts(message, io: $stdout) if Rake.application.options.always_multitask
        message = yield(message) if block_given?
        message
      end

      def readline(command)
        prompt = StringIO.new
        safe_puts(cmd('').lines.last, io: prompt, force: true)

        my_command = RakeTask.mutex.synchronize do
          Readline.pre_input_hook = lambda do
            Readline.insert_text(command)
            Readline.redisplay
          end

          Readline.readline("\e[E\e[K#{prompt.string.chomp}", true)
        end

        case my_command.strip
        when /^\s*#/, ''
          # do nothing and skip this command
        when command.strip
          cmd(my_command)
        else
          cmd(my_command)
          # retry thid command
          readline(command)
        end
      end

      def sync(&block)
        RakeTask.mutex.synchronize(&block) if block
      end
    end

  end
end
