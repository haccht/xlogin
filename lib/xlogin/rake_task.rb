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
          desc "#{description} - #{hostname}" if opts[:desc] == true
          RakeTask.new(hostname, &block)
        end

      end
    end

    attr_reader   :name
    attr_accessor :lock
    attr_accessor :log
    attr_accessor :timeout
    attr_accessor :silent
    attr_accessor :fail_on_error

    @@stopped = false

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
          run_task unless @@stopped
          touch(lock, verbose: Rake.application.options.trace) unless @@stopped
        end
      else
        task(name) do
          run_task unless @@stopped
        end
      end
    end

    def run_task
      buffer = StringIO.new

      logger = log ? [log] : []
      logger.push $stdout if !silent && !Rake.application.options.always_multitask
      logger.push buffer  if !silent &&  Rake.application.options.always_multitask

      session = Xlogin.get(name, log: logger, timeout: timeout)
      def session.comment(text, prefix: "[INFO]", **color)
        color = {color: :green}.merge(**color)

        log("\n")
        log(Time.now.iso8601.colorize(**color) + ' ') if !Rake.application.options.always_multitask
        log("#{prefix} #{text}".colorize(**color))
        cmd('')
      end

      @runner.call(session)
      $stdout.print format_log(buffer.string)
    rescue => e
      session.comment("#{e}", prefix: "[ERROR]", color: :red)
      $stderr.print format_log(buffer.string)

      @@stopped = true if fail_on_error
    ensure
      session.close rescue nil
    end

    def format_log(text)
      text.lines.map do |line|
        "#{Time.now.iso8601} - #{name}\t|#{line.gsub(/^\s*[\r]+/, '')}"
      end.join
    end

  end
end
