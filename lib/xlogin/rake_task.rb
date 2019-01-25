require 'time'
require 'rake'
require 'rake/tasklib'
require 'ostruct'
require 'stringio'

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
    attr_accessor :silent
    attr_accessor :fail_on_error

    @@graceful_shutdown = false

    def initialize(name)
      @name     = name
      @runner   = nil
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
          next if @@graceful_shutdown
          run_task
          touch(lock, verbose: Rake.application.options.trace)
        end
      else
        task(name) do
          next if @@graceful_shutdown
          run_task
        end
      end
    end

    def run_task
      buffer  = StringIO.new
      loggers = []
      loggers << log     if log
      loggers << buffer  if !silent &&  Rake.application.options.always_multitask
      loggers << $stdout if !silent && !Rake.application.options.always_multitask

      session = Xlogin.get(name, log: loggers)
      @runner.call(session)
      session.close rescue nil

      printf($stdout, buffer.string) if !silent && Rake.application.options.always_multitask
    rescue => e
      output($stderr, buffer.string) if !silent && Rake.application.options.always_multitask
      output($stderr, "[ERROR] #{e}\n")

      @@graceful_shutdown = true if fail_on_error
    end

    def printf(fp, text)
      time = Time.now.iso8061
      text.each_line do |line|
        fp.print "#{time} "
        fp.print "#{name}\t" if Rake.application.options.always_multitask
        fp.print "|#{line.chomp.gsub(/^\s*\r/, '')}\n"
      end
    end

  end
end
