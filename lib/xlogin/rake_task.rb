require 'rake'
require 'rake/tasklib'
require 'stringio'

module Xlogin
  class RakeTask < Rake::TaskLib

    class << self
      include Rake::DSL

      def bulk(names, description = nil, &block)
        current_namespace do |path|
          description ||= Rake.application.last_description

          names = names.map(&:strip).grep(/^\s*[^#]/).uniq
          names.each do |name|
            desc description || "Run '#{path}:#{name}'"
            RakeTask.new(name, &block)
          end
        end
      end

      def current_namespace
        Rake.application.current_scope.path.tap do |path|
          if path.empty?
            path = self.name.split('::').first.downcase
            namespace(path) { yield(path) } if block_given?
          else
            yield(path) if block_given?
          end
        end
      end
    end


    attr_reader   :name
    attr_accessor :lock
    attr_accessor :log
    attr_accessor :silent

    def initialize(name, description = Rake.application.last_description)
      @name   = name
      @desc   = description
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
      RakeTask.current_namespace do |path|
        desc @desc || "Run '#{path}:#{name}'"

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
          lines = buffer.string.lines.map { |line| "#{name}\t" + line.gsub("\r", '') }
          lines.each { |line| $stdout.print line.chomp + "\n" }
        rescue => e
          lines = buffer.string.lines.map { |line| "#{name}\t" + line.gsub("\r", '') }
          lines.each { |line| $stdout.print line.chomp + "\n" }
          $stderr.puts "#{name}\t#{e}"
        end
      else
        loggers << $stdout unless silent

        begin
          session = Xlogin.factory.build_from_hostname(name, log: loggers)
          @runner.call(session)
        rescue => e
          $stderr.puts e
        end
      end
    end

  end
end
