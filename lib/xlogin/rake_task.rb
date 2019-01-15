require 'time'
require 'rake'
require 'rake/tasklib'
require 'ostruct'
require 'stringio'

module Xlogin

  class RakeTask < Rake::TaskLib

    class << self
      include Rake::DSL

      def generate(*target, **opts, &block)
        hostnames = target.flat_map { |e| Xlogin.list(e) }.map { |e| e[:name] }

        description = Rake.application.last_description
        task 'all' => hostnames unless opts[:bundle] == false

        description = opts[:desc] if opts.key?(:desc)
        hostnames.each do |hostname|
          desc description
          RakeTask.new(hostname, &block)
        end

      end
    end

    attr_reader   :name
    attr_reader   :taskname
    attr_accessor :lock
    attr_accessor :log
    attr_accessor :silent
    attr_accessor :fail_on_error

    def initialize(name)
      @name     = name
      @taskname = [*Rake.application.current_scope.to_a.reverse, name].join(':')
      @runner   = nil
      @config   = OpenStruct.new
      @silent ||= Rake.application.options.silent
      @fail_on_error = true

      yield self if block_given?
      define
    end

    def run(&block)
      @runner = block
    end

    def method_missing(name, *args, &block)
      super(name, *args, &block) unless name.to_s =~ /^\w+=$/
      @config.send(name, *args)
    end

    private
    def define
      description = Rake.application.last_description
      description = "#{description} - #{name}" if description
      desc description

      mkdir_p(File.dirname(log),  verbose: Rake.application.options.trace) if log
      mkdir_p(File.dirname(lock), verbose: Rake.application.options.trace) if lock

      if lock
        task(name => lock)
        file(lock) do
          run_task
          mkdir_p(File.dirname(lock), verbose: Rake.application.options.trace)
          touch(lock, verbose: Rake.application.options.trace)
        end
      else
        task(name) do
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

      begin
        session = Xlogin.get(name, log: loggers, **@config.to_h)
        @runner.call(session)
        session.close if session

        printf($stdout, buffer.string) if !silent && Rake.application.options.always_multitask
      rescue => e
        printf($stderr, buffer.string) if !silent && Rake.application.options.always_multitask
        printf($stderr, "[ERROR] Xlogin - #{e}\n")
        raise e if fail_on_error
      end
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
