require 'rake'
require 'rake/tasklib'
require 'ostruct'
require 'stringio'

module Xlogin

  class RakeTask < Rake::TaskLib

    class << self
      include Rake::DSL

      def generate(*target, **opts, &block)
        hostnames = target.flat_map { |e| Xlogin.factory.list_info(e) }.map { |e| e[:name] }

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
    attr_accessor :lock
    attr_accessor :log
    attr_accessor :silent
    attr_accessor :fail_on_error

    def initialize(name)
      @name   = name
      @runner = nil
      @config = OpenStruct.new
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
        session.instance_eval(&@runner)
        session.close if session

        output($stdout, buffer.string) if !silent && Rake.application.options.always_multitask
      rescue => e
        output($stderr, buffer.string) if !silent && Rake.application.options.always_multitask
        output($stderr, "[ERROR] Xlogin - #{e}\n")
        raise e if fail_on_error
      end
    end

    def output(fp, text)
      prefix = (Rake.application.options.always_multitask)? "#{name}\t|" : ""
      lines  = text.lines.map { |line| "#{prefix}#{line.strip}\n" }
      lines.each { |line| $stdout.print line }
    end

  end

end
