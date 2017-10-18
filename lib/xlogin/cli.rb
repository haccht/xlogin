#! /usr/bin/env ruby

require 'optparse'
require 'ostruct'
require 'parallel'
require 'stringio'

module Xlogin
  class CLI

    def self.run(args = ARGV)
      config = getopts(args)
      client = Xlogin::CLI.new

      task = config.task.downcase.tr('-', '_')
      Xlogin::CLI.usage("Task not defined - #{task}") unless client.respond_to?(task)
      client.method(task).call(config)
    end

    def self.getopts(args)
      config = OpenStruct.new(
        task: 'tty',
        hostlist:  [],
        parallels: 5,
        inventory: nil,
        templates: [],
      )

      parser = OptionParser.new
      parser.banner += ' HOST-PATTERN'

      parser.on('-m TASK', '--task', String, 'Execute the TASK(default: tty).') { |v| config.task = v }
      parser.on('-a ARGS', '--args', String, 'The ARGS to pass to the task.')   { |v| config.args = v }

      parser.on('-i PATH',      '--inventory',    String, 'The PATH to the inventory file (default: $HOME/.xloginrc).') { |v| config.inventory = v }
      parser.on('-t PATH',      '--template',     String, 'The PATH to the template file.')       { |v| config.templates << v }
      parser.on('-T DIRECTORY', '--template-dir', String, 'The DIRECTORY to the template files.') { |v| config.templates += Dir.glob(File.join(v, '*.rb')) }
      parser.on('-l [DIRECTORY]', '--log',        String, 'The DIRECTORY to the output log file (default: $PWD/log).') { |v| config.logdir = v || Dir.pwd }

      parser.on('-p NUM', '--parallels',  Integer,   'The NUM of the threads. (default: 5).') { |v| config.parallels  = v }
      parser.on('-e',     '--enable',     TrueClass, 'Try to gain enable priviledge.')        { |v| config.enable = v }
      parser.on('-y',     '--assume-yes', TrueClass, 'Always answer "yes" if confirmed.')     { |v| config.assume_yes = v }
      parser.on('-h',     '--help', 'Show this message.') { Xlogin::CLI.usage }

      self.class.module_eval do
        define_method(:usage) do |message = nil|
          puts message if message
          puts parser.to_s
          exit 1
        end
      end

      Xlogin.configure do
        template(*config.templates)
        source(config.inventory)
        authorize(config.assume_yes)
      end

      config.hostlist += parser.parse(args).flat_map do |target|
        hostlist = Xlogin.factory.list(target)
        hostlist.tap { |e| raise "Invalid inventory - #{target}" if e.empty? }
      end

      config.parallels = [config.parallels, config.hostlist.size].min
      config
    end

    def tty(config)
      config.hostlist = [config.hostlist.shift].compact
      Xlogin::CLI.usage('Invalid inventory.') if config.hostlist.empty?

      puts "Trying #{config.hostlist.first[:name]}..."
      puts "Escape character is '^]'."

      login(config) do |session|
        session.interact!
      end
    end

    def exec(config)
      Xlogin::CLI.usage('Invalid inventory.') if config.hostlist.empty?

      login(config) do |session|
        command_lines = ['', *config.args.split(';')]
        command_lines.each { |command| session.cmd(command) }
      end
    end

    def load(config)
      Xlogin::CLI.usage('Invalid inventory.') if config.hostlist.empty?

      login(config) do |session|
        command_lines = ['', *IO.readlines(config.args.to_s)]
        command_lines.each { |command| session.cmd(command) }
      end
    end

    def list(config)
      config.hostlist += Xlogin.factory.list('all') if config.hostlist.empty?
      width = config.hostlist.map { |e| e[:name].length }.max
      puts config.hostlist.map { |e| "#{e[:name].to_s.ljust(width)} #{e[:type]}" }.sort
    end

    private
    def login(config, &block)
      display = Mutex.new
      buffer  = StringIO.new

      Parallel.map(config.hostlist, in_thread: config.parallels) do |hostinfo|
        begin
          hostname = hostinfo[:name]

          loggers  = []
          loggers << buffer  if config.parallels != 1
          loggers << $stdout if config.parallels == 1
          loggers << File.join(config.logdir, "#{hostname}.log") if config.logdir

          session = Xlogin.factory.build(hostinfo.merge(log: loggers))
          session.enable(session.opts.enable) if config.enable && session.respond_to?(:enable)

          block.call(session)
        rescue => e
          lines = (config.parallels > 1)? "\n#{hostname}\t[Error] #{e}" : "\n[Error] #{e}"
          display.synchronize { $stderr.puts lines }
        end

        if config.parallels > 1
          lines = buffer.string.lines.map { |line| "#{hostname}\t" + line.gsub("\r", '') }
          display.synchronize { $stdout.puts lines }
        end
      end
    end

  end
end
