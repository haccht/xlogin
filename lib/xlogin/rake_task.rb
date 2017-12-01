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

    def initialize(name)
      @name   = name
      @runner = nil
      @silent ||= Rake.application.options.silent

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
      loggers = []

      if log
        mkdir_p(File.dirname(log), verbose: Rake.application.options.trace)
        loggers << log
      end

      if Rake.application.options.always_multitask
        buffer = StringIO.new
        loggers << buffer  unless silent

        begin
          session = Xlogin.factory.build_from_hostname(name, log: loggers)
          @runner.call(session)
          session.close if session
          lines = buffer.string.lines.map { |line| "#{name}\t" + line.gsub("\r", '') }
          lines.each { |line| $stdout.print line.chomp + "\n" }
        rescue => e
          lines = buffer.string.lines.map { |line| "#{name}\t" + line.gsub("\r", '') }
          lines.each { |line| $stdout.print line.chomp + "\n" }
          $stderr.print "#{name}\t#{e}\n"
        end
      else
        loggers << $stdout unless silent

        begin
          session = Xlogin.factory.build_from_hostname(name, log: loggers)
          @runner.call(session)
          session.close if session
        rescue => e
          $stderr.print "#{e}\n"
        end
      end
    end

  end
end
