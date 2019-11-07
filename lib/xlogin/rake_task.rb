require 'time'
require 'rake'
require 'rake/tasklib'
require 'ostruct'
require 'stringio'
require 'colorize'

module Xlogin
  class RakeTask < Rake::TaskLib

    class << self
      include Rake::DSL

      def generate(*patterns, **opts, &block)
        description = Rake.application.last_description
        hostnames   = Xlogin.list(*patterns).map { |e| e[:name] }

        task 'all' => hostnames unless opts[:all] == false
        hostnames.each do |hostname|
          desc "#{description} @#{hostname}" if opts[:all] == false
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
    attr_accessor :lock
    attr_accessor :log
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

    def name_with_scope
      [*Rake.application.current_scope.to_a.reverse, name].join(':')
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
      buffer = StringIO.new

      logger = log ? [log] : []
      logger.push buffer
      logger.push $stdout if !silent && !Rake.application.options.always_multitask

      session = Xlogin.get(name, log: logger, timeout: timeout)

      @runner.call(session)
      $stdout.print format_log(buffer.string) if !silent && Rake.application.options.always_multitask

      return true
    rescue => e
      RakeTask.shutdown! if fail_on_error

      buffer.puts("\n[ERROR] #{e}".colorize(color: :white, background: :red))
      $stderr.print "\n" + format_log(buffer.string.chomp).colorize(color: :light_red)
      $stderr.print "\n"

      return false
    ensure
      session.close rescue nil
    end

    def format_log(text)
      text.lines.map do |line|
        "#{Time.now.iso8601} - #{name}\t|#{line.gsub(/^\s*[\r]+/, '')}"
      end.join
    end

  end

  module SessionModule
    def msg(text, prefix: "[INFO]", chomp: false, **color)
      default_color = { color: :green }

      log("\n")
      log(Time.now.iso8601.colorize(**color) + ' ') if !Rake.application.options.always_multitask

      log("#{prefix} #{text}".colorize(**default_color.merge(color)))
      cmd('') unless chomp
    end
  end
end
