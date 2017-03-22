require 'rake'
require 'rake/tasklib'
require 'readline'
require 'thread'

module Xlogin
  class RakeTask < Rake::TaskLib

    class << self
      include Rake::DSL

      def bulk(names, &block)
        names = names.map(&:strip).grep(/^\s*[^#]/)

        namecount = names.uniq.inject({}) { |a, e| a.merge(e => names.count(e)) }
        duplicate = namecount.keys.select { |name| namecount[name] > 1 }
        raise Xlogin::GeneralError.new("Duplicate hosts found - #{duplicate.join(', ')}") unless duplicate.empty?

        current_namespace do
          description = Rake.application.last_description || "Run '#{RakeTask.current_namespace}'"

          desc description
          task all: names

          names.each do |name|
            desc "#{description} -> '#{name}'"
            RakeTask.new(name, &block)
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
    attr_accessor :timeout

    def initialize(name, *args)
      @name          = name

      @fail_on_error = true
      @silent        = false
      @lockfile      = nil
      @logfile       = nil
      @timeout       = nil

      @session       = nil
      @taskrunner    = nil

      yield self if block_given?
      define
    end

    def start(&block)
      @taskrunner = block
    end

    def puts(*messages, io: $stdout)
      RakeTask.mutex.synchronize do
        messages.flat_map { |message| message.to_s.lines }.each do |line|
          line.gsub!("\r", "")
          io.puts (Rake.application.options.always_multitask)? "#{name}\t#{line}" : line
        end
      end
    end

    private
    def define
      RakeTask.current_namespace do
        description = Rake.application.last_description || "Run '#{RakeTask.current_namespace}'"
        desc "#{description} -> '#{name}'"

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

        [logfile, lockfile].each do |file|
          next unless file

          desc 'Remove any temporary products'
          task 'clean' do
            rm(file, verbose: true) if File.exist?(file)
          end
        end
      end
    end

    def run_task
      loggers = []
      loggers << $stdout unless silent || Rake.application.options.silent || Rake.application.options.always_multitask

      if logfile
        mkdir_p(File.dirname(logfile), verbose: Rake.application.options.trace)
        loggers << logfile if logfile
      end

      xlogin_opts = Hash.new
      xlogin_opts[:log]     = loggers unless loggers.empty?
      xlogin_opts[:timeout] = timeout if timeout

      @session = Xlogin.get(name, xlogin_opts)

      @session.extend(SessionExt)
      @session.puts_proc = self.method(:puts)

      @taskrunner.call(@session) if @taskrunner
    rescue => e
      raise e if fail_on_error
      self.puts(e, io: $stdout)
    end

    module SessionExt
      def puts_proc=(method)
        @puts_proc = method
      end

      def cmd(*args)
        super(*args).tap do |message|
          break message if Rake.application.options.silent || !Rake.application.options.always_multitask
          @puts_proc.call(message, io: $stdout)
        end
      end

      def readline(command)
        prompt = StringIO.new
        @puts_proc.call(cmd('').lines.last, io: prompt)

        my_command = RakeTask.mutex.synchronize do
          Readline.pre_input_hook = lambda do
            Readline.insert_text(command)
            Readline.redisplay
          end

          Readline.readline("\e[E\e[K#{prompt.string.chomp}", false)
        end

        case my_command.strip
        when /^\s*#/, ''
          # do nothing and skip
        when command.strip
          cmd(my_command)
        else
          cmd(my_command)
          readline(command)
        end
      end
    end

  end
end
