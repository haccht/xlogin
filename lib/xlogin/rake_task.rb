require 'rake'
require 'rake/tasklib'
require 'stringio'

module Xlogin

  class RakeTask < Rake::TaskLib

    class << self
      include Rake::DSL

      def bulk(names, &block)
        names = names.map(&:strip).grep(/^\s*[^#]/).uniq
        description = Rake.application.last_description

        names.each do |name|
          desc description
          RakeTask.new(name, &block)
        end
      end
    end

    attr_reader   :name
    attr_accessor :lock
    attr_accessor :log
    attr_accessor :silent
    attr_accessor :timeout
    attr_accessor :fail_on_error

    def initialize(name)
      @name   = name
      @runner = nil
      @silent ||= Rake.application.options.silent
      @fail_on_error = true

      yield(self) if block_given?
      define_task
    end

    def start(&block)
      @runner = block
    end

    private
    def define_task
      description = Rake.application.last_description
      description = "#{description} - #{name}" if description
      desc description

      if lock
        task(name => lock)
        file(lock) do
          invoke
          mkdir_p(File.dirname(lock), verbose: Rake.application.options.trace)
          touch(lock, verbose: Rake.application.options.trace)
        end
      else
        task(name) { invoke }
      end
    end

    def invoke
      buffer  = StringIO.new
      loggers = []
      loggers << buffer  if Rake.application.options.always_multitask
      loggers << $stdout unless Rake.application.options.always_multitask || silent

      if log
        mkdir_p(File.dirname(log), verbose: Rake.application.options.trace)
        loggers << log
      end

      begin
        session = Xlogin.factory.build_from_hostname(name, log: loggers, timeout: timeout)
        @runner.call(session)
        session.close if session
      rescue => e
        $stderr.print "[ERROR] #{name} - #{e}\n"
        raise e if fail_on_error
      end

      if Rake.application.options.always_multitask && !silent
        lines = buffer.string.lines.map { |line| "#{name}\t" + line.gsub("\r", '') }
        lines.each { |line| $stdout.print "#{line.chomp}\n" }
      end
    end

  end

  # monkey patch to SessionModule#cmd method
  module SessionModule
    def cmd(*args)
      super(*args) { |resp| yield resp if block_given? }
    end
  end

end
