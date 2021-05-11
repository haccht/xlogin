require 'time'
require 'rake'
require 'rake/tasklib'
require 'stringio'
require 'colorize'

module Xlogin
  class RakeTask < Rake::TaskLib

    class << self
      include Rake::DSL

      def all(*patterns, &block)
        description = Rake.application.last_description
        task all: Xlogin.list(*patterns).map{ |e| e[:name] }

        desc description
        generate(*patterns, &block)
      end

      def generate(*patterns, &block)
        description = Rake.application.last_description

        hostnames = Xlogin.list(*patterns).map{ |e| e[:name] }
        hostnames.each do |hostname|
          desc "#{description} - #{hostname}" if description
          RakeTask.new(hostname, &block)
        end
      end

      def shutdown!
        @stop = true
      end

      def stop?
        !!@stop
      end
    end

    attr_reader   :name
    attr_accessor :log
    attr_accessor :lock
    attr_accessor :timeout
    attr_accessor :silent
    attr_accessor :fail_on_error

    def initialize(name)
      @name     = name
      @runner   = nil
      @timeout  = nil
      @silent ||= Rake.application.options.silent
      @fail_on_error = true

      yield self if block_given?
      define
    end

    def name_with_scope(separator = ':')
      [*Rake.application.current_scope.to_a.reverse, name].join(separator)
    end

    def run(&block)
      @runner = block
    end
    alias_method :start, :run

    private
    def define
      mkdir_p(File.dirname(log),  verbose: Rake.application.options.trace) if log
      mkdir_p(File.dirname(lock), verbose: Rake.application.options.trace) if lock

      if lock
        task(name => lock)
        file(lock) do
          next if RakeTask.stop?
          run_task && touch(lock, verbose: Rake.application.options.trace)
        end
      else
        task(name) do
          next if RakeTask.stop?
          run_task
        end
      end
    end

    def run_task
      buffer  = StringIO.new
      loggers = [buffer]
      loggers << log    if log
      loggers << STDOUT if !silent && !Rake.application.options.always_multitask

      session = Xlogin.get(name, log: loggers, timeout: timeout)
      instance_exec(session, &@runner)

      print(buffer.string) if !silent && Rake.application.options.always_multitask
      return true
    rescue => e
      RakeTask.shutdown! if fail_on_error

      session.log_message(e.to_s.colorize(color: :red)) if session
      print(buffer.string + "\n", color: :red) if Rake.application.options.always_multitask
      return false
    ensure
      session.close rescue nil
    end

    def puts(text, **opts)
      return text.each { |e| puts(e, **opts) } if text.kind_of?(Array)

      text = text.to_s
      text = text + "\n" unless text[-1] == "\n"
      print(text, **opts)
    end

    def print(text, **opts)
      text = text.to_s
      return if text.empty?

      text = text.gsub("\r", '')
      text = text.lines.map{ |text| "#{name}\t|#{text}" }.join if Rake.application.options.always_multitask
      text = text.colorize(**opts)
      $stdout.print(text)
    end

  end
end
