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
        module: 'tty',
        inventory: DEFAULT_INVENTORY_PATH,
        templates: Dir.glob(File.join(DEFAULT_TEMPLATE_DIR, '*.rb')),
        forks: 5,
      )

      parser = OptionParser.new
      parser.banner += ' HOST-PATTERN'

      parser.on('-m MODULE',    '--module', String, 'Execute the module called NAME (default: tty).') { |v| config.module = v }
      parser.on('-a ARGUMENTS', '--args',   String, 'The ARGUMENTS to pass to the module.')           { |v| config.args= v }

      parser.on('-i PATH',      '--inventory',    String, 'The PATH to the inventory file (default: $HOME/.xloginrc).') { |v| config.inventory = v }
      parser.on('-t PATH',      '--template',     String, 'The PATH to the template file.')       { |v| config.templates << v }
      parser.on('-T DIRECTORY', '--template-dir', String, 'The DIRECTORY to the template files.') { |v| config.templates += Dir.glob(File.join(v, '*.rb')) }
      parser.on('-l [DIRECTORY]', '--log',        String, 'The DIRECTORY to the output log file (default: $PWD/log).') { |v| config.logdir = v || Dir.pwd }

      parser.on('-f NUM', '--forks',     Integer,   'Level of parallelism. (default: 1).') { |v| config.forks     = v }
      parser.on('-e',     '--enable',    TrueClass, 'Try to gain enable priviledge.')      { |v| config.enable    = v }
      parser.on('-y',     '--assumeyes', TrueClass, 'Answer "yes" for all confirmations.') { |v| config.assumeyes = v }
      parser.on('-h',     '--help', 'Show this message.') { Xlogin::CLI.usage }

      if config.templates.empty?
        FileUtils.mkdir_p(DEFAULT_TEMPLATE_DIR)
        Xlogin::BUILTIN_TEMPLATE_FILES.each { |file| FileUtils.cp(file, DEFAULT_TEMPLATE_DIR) }
        config.templates = Dir.glob(File.join(DEFAULT_TEMPLATE_DIR, '*.rb'))
      end

      self.class.module_eval do
        define_method(:usage) do |message = nil|
          puts message, '' if message
          puts parser.to_s
          exit 1
        end
      end

      config.hostnames = parser.parse(args)
      config
    end

    def self.run(args = ARGV)
      config = getopts(args)
      client = Xlogin::CLI.new(config)

      Xlogin::CLI.usage("Module not found - #{config.module}") unless client.respond_to?(config.module)
      client.method(config.module).call
    end


    def initialize(config)
      Xlogin.source(config.inventory)
      Xlogin.load_templates(*config.templates)

      @config = config
    end

    def list
      puts Xlogin.factory.list.map { |e| "#{e[:name]}\t#{e[:type]}" }
    end

    def tty
      @config.hostnames = [@config.hostnames.shift]
      Xlogin::CLI.usage('Invalid HOST-PATTERN') if @config.hostnames.empty?

      puts "Trying #{@config.hostnames.first}..."
      puts "Escape character is '^]'."

      login do |session|
        session.interact!
      end
    end

    def command
      Xlogin::CLI.usage('Missing argument') unless @config.args

      login do |session|
        command_lines = ['', *@config.args.split(';')]
        command_lines.each { |command| session.cmd(command) }
      end
    end

    def load
      Xlogin::CLI.usage('Missing argument') unless @config.args

      login do |session|
        command_lines = ['', *IO.readlines(@config.args.to_s)]
        command_lines.each { |command| session.cmd(command) }
      end
    end

    private
    def login
      display = Mutex.new
      @config.forks = [@config.forks, @config.hostnames.size].min
      FileUtils.mkdir_p(@config.logdir) if @config.logdir

      Parallel.each(@config.hostnames, in_thread: @config.forks) do |hostname|
        begin
          buffer  = StringIO.new

          loggers = []
          loggers << buffer  if @config.forks != 1
          loggers << $stdout if @config.forks == 1
          loggers << File.join(@config.logdir, "#{hostname}.log") if @config.logdir

          session = Xlogin.get(hostname, assumeyes: @config.assumeyes, enable: @config.enable, log: loggers)
          yield session

          if @config.forks > 1
            output = buffer.string.lines.map { |line| "#{hostname}: #{line}" }.join
            display.synchronize { $stdout.puts output }
          end
        rescue => e
          if @config.forks > 1
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
