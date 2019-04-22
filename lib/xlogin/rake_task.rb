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
        patterns    = ['*'] if patterns.empty?
        description = Rake.application.last_description
        hostnames   = Xlogin.list(*patterns).map { |e| e[:name] }

        task 'all' => hostnames unless opts[:all] == false
        hostnames.each do |hostname|
          desc "#{description} - #{hostname}" if opts[:desc] == true
          RakeTask.new(hostname, &block)
        end

      end

      def printf(fp, text)
        time = Time.now.iso8601
        fp.print "\n"
        text.chomp.each_line do |line|
          fp.print "#{time} "
          fp.print "#{name}\t" if Rake.application.options.always_multitask
          fp.print "|#{line.gsub(/^\s*[\r\n]+/, '')}\n"
        end
      end
    end

    attr_reader   :name
    attr_accessor :lock
    attr_accessor :log
    attr_accessor :timeout
    attr_accessor :silent
    attr_accessor :fail_on_error

    @@graceful_shutdown = false

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
          run_task unless @@graceful_shutdown
          touch(lock, verbose: Rake.application.options.trace) unless @@graceful_shutdown
        end
      else
        task(name) do
          run_task unless @@graceful_shutdown
        end
      end
    end

    def run_task
      buffer = StringIO.new

      args = Hash.new
      args[:log] = []
      args[:log] << log     if log
      args[:log] << buffer  if !silent &&  Rake.application.options.always_multitask
      args[:log] << $stdout if !silent && !Rake.application.options.always_multitask
      args[:timeout] = timeout if timeout

      session = Xlogin.get(name, **args)
      @runner.call(session)
      session.close rescue nil

      RakeTask.printf($stdout, buffer.string) if !silent && Rake.application.options.always_multitask
    rescue => e
      RakeTask.printf($stderr, buffer.string) if !silent && Rake.application.options.always_multitask
      RakeTask.printf($stderr, "ERROR - #{e}\n")

      @@graceful_shutdown = true if fail_on_error
    end

  end
end
