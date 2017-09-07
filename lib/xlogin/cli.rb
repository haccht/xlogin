#! /usr/bin/env ruby

require 'fileutils'
require 'optparse'
require 'ostruct'
require 'parallel'
require 'readline'
require 'stringio'
require 'thread'

module Xlogin
  class CLI

    DEFAULT_INVENTORY_PATH = File.join(ENV['HOME'], '.xloginrc')
    DEFAULT_TEMPLATE_DIR   = File.join(ENV['HOME'], '.xlogin.d')

    def self.getopts(args)
      config = OpenStruct.new(
        func: 'tty',
        inventory: DEFAULT_INVENTORY_PATH,
        parallels: 5,
        templates: [],
        hostexprs: [],
        hostlist:  [],
      )

      parser = OptionParser.new
      parser.banner += ' HOST-PATTERN'

      parser.on('-f FUNCTION',  '--func', String, 'Execute the FUNCTION (default: tty).')   { |v| config.func = v }
      parser.on('-a ARGUMENTS', '--args', String, 'The ARGUMENTS to pass to the function.') { |v| config.args = v }

      parser.on('-i PATH',      '--inventory',    String, 'The PATH to the inventory file (default: $HOME/.xloginrc).') { |v| config.inventory = v }
      parser.on('-t PATH',      '--template',     String, 'The PATH to the template file.')       { |v| config.templates << v }
      parser.on('-T DIRECTORY', '--template-dir', String, 'The DIRECTORY to the template files.') { |v| config.templates += Dir.glob(File.join(v, '*.rb')) }
      parser.on('-l [DIRECTORY]', '--log',        String, 'The DIRECTORY to the output log file (default: $PWD/log).') { |v| config.logdir = v || Dir.pwd }

      parser.on('-p NUM', '--parallels', Integer,   'The NUM of the threads. (default: 5).') { |v| config.parallels = v }
      parser.on('-e',     '--enable',    TrueClass, 'Try to gain enable priviledge.')        { |v| config.enable    = v }
      parser.on('-y',     '--assumeyes', TrueClass, 'Always answer "yes" if confirmed.')     { |v| config.assumeyes = v }
      parser.on('-h',     '--help', 'Show this message.') { Xlogin::CLI.usage }

      self.class.module_eval do
        define_method(:usage) do |message = nil|
          puts message, '' if message
          puts parser.to_s
          exit 1
        end
      end

      config.hostexprs = parser.parse(args)
      config.templates = Dir.glob(File.join(DEFAULT_TEMPLATE_DIR, '*.rb')) if config.templates.empty?

      Xlogin.init do
        source(config.inventory)
        template(*config.templates)
      end

      factory = Xlogin::FirmwareFactory.instance
      config.hostlist += config.hostexprs.flat_map { |expr| factory.list(expr) }
      config
    end

    def self.run(args = ARGV)
      config = getopts(args)
      client = Xlogin::CLI.new
      func   = config.func.gsub(/([a-z\d])([A-Z])/, '\1_\2').gsub(/[-_]+/, '_').downcase

      Xlogin::CLI.usage("Function not found - #{config.func}") unless client.respond_to?(func)
      client.method(func).call(config)
    end

    def list(config)
      if config.hostexprs.empty?
        factory = Xlogin::FirmwareFactory.instance
        config.hostlist = factory.list
      end

      length = config.hostlist.map { |e| e[:name].length }.max
      matrix = config.hostlist.map { |e| "#{e[:name].to_s.ljust(length)} #{e[:type]}" }.sort
      puts matrix
    end

    def tty(config)
      Xlogin::CLI.usage('Invalid HOST-PATTERN') if config.hostlist.empty?

      puts "Trying #{config.hostlist.first}..."
      puts "Escape character is '^]'."

      config.hostlist = [config.hostlist.shift]
      login(config) do |session|
        session.interact!
      end
    end

    def command(config)
      Xlogin::CLI.usage('Missing argument') unless config.args

      login(config) do |session|
        command_lines = ['', *config.args.split(';')]
        command_lines.each { |command| session.cmd(command) }
      end
    end

    def command_load(config)
      Xlogin::CLI.usage('Missing argument') unless config.args

      login(config) do |session|
        command_lines = ['', *IO.readlines(config.args.to_s)]
        command_lines.each { |command| session.cmd(command) }
      end
    end

    private
    def login(config)
      display = Mutex.new
      config.parallels = [config.parallels, config.hostlist.size].min
      FileUtils.mkdir_p(config.logdir) if config.logdir

      Parallel.each(config.hostlist, in_thread: config.parallels) do |host|
        begin
          hostname = host[:name]
          buffer   = StringIO.new
          loggers  = []
          loggers << buffer  if config.parallels != 1
          loggers << $stdout if config.parallels == 1
          loggers << File.join(config.logdir, "#{hostname}.log") if config.logdir

          session = Xlogin.get(hostname, assumeyes: config.assumeyes, enable: config.enable, log: loggers)
          yield session

          if config.parallels > 1
            output = buffer.string.lines.map { |line| "#{hostname}: #{line}" }.join
            display.synchronize { $stdout.puts output }
          end
        rescue => e
          if config.parallels > 1
            output = "\n#{hostname}: [Error] #{e}"
            display.synchronize { $stderr.puts output }
          else
            output = "\n[Error] #{e}"
            display.synchronize { $stderr.puts output }
          end
        end
      end
    end

  end
end
