#! /usr/bin/env ruby

require 'optparse'
require 'ostruct'
require 'parallel'
require 'stringio'

module Xlogin
  class CLI

    DEFAULT_INVENTORY_FILE = File.join(ENV['HOME'], '.xloginrc')
    DEFAULT_TEMPLATE_DIR   = File.join(ENV['HOME'], '.xlogin.d')

    def self.run(args = ARGV)
      config = getopts(args)
      client = Xlogin::CLI.new
      client.method(config.taskname).call(config)
    end

    def self.getopts(args)
      config = OpenStruct.new(
        parallel:  1,
        inventory: nil,
        templates: [],
      )

      parser = OptionParser.new
      parser.banner  = "#{File.basename($0)} HOST [TASK ARGUMENTS] [Options]"
      parser.version = Xlogin::VERSION

      parser.on('-i PATH',        '--inventory',    String, 'The PATH to the inventory file(default: $HOME/.xloginrc).') { |v| config.inventory = v }
      parser.on('-t PATH',        '--template',     String, 'The PATH to the template file.') { |v| config.templates << v }
      parser.on('-T DIRECTORY',   '--template-dir', String, 'The DIRECTORY of the template files.') { |v| config.templates += Dir.glob(File.join(v, '*.rb')) }
      parser.on('-L [DIRECTORY]', '--log-dir',      String, 'The DIRECTORY of the log files(default: $PWD).') { |v| config.logdir = v || '.' }

      parser.on('-j NUM', '--jobs',       Integer,   'The NUM of jobs to execute in parallel(default: 1).') { |v| config.parallel = v }
      parser.on('-e',     '--enable',     TrueClass, 'Try to gain enable priviledge.') { |v| config.enable = v }
      parser.on('-y',     '--assume-yes', TrueClass, 'Automatically answer yes to prompts.') { |v| config.authorize = v }

      begin
        args = parser.parse!(args)
        hostlist = args.shift
        taskname = args.shift || 'tty'

        Xlogin.configure do
          config.inventory ||= DEFAULT_INVENTORY_FILE
          if config.templates.empty?
            generate_templates(DEFAULT_TEMPLATE_DIR) unless File.exist?(DEFAULT_TEMPLATE_DIR)
            config.templates += Dir.glob(File.join(DEFAULT_TEMPLATE_DIR, '*.rb'))
          end

          authorize(config.authorize)
          source(File.expand_path(config.inventory, ENV['PWD']))
          load_templates(*config.templates.map { |file| File.expand_path(file, ENV['PWD']) })
        end

        config.hostlist  = hostlist.to_s.split(',').flat_map { |pattern| Xlogin.factory.list(pattern) }
        config.taskname  = taskname.to_s.downcase.tr('-', '_')
        config.arguments = args

        methods = Xlogin::CLI.instance_methods(false)
        raise "No host found: `#{hostlist}`"   if config.hostlist.empty?
        raise "No task defined: `#{taskname}`" if config.taskname.empty? || methods.find_index(config.taskname.to_sym).nil?
      rescue => e
        $stderr.puts e, '', parser
        exit 1
      end

      config
    end

    def list(config)
      width = config.hostlist.map { |e| e[:name].length }.max
      $stdout.puts config.hostlist.map { |e| "#{e[:name].to_s.ljust(width)} #{e[:type]}" }.sort
    end

    def tty(config)
      target = config.hostlist.sort_by { |e| e[:name] }.first
      $stdout.puts "Trying #{target[:name]}...", "Escape character is '^]'."
      config.hostlist = [target]
      login(config) { |session| session.interact! }
    end

    def exec(config)
      command_lines = ['', *config.arguments.flat_map { |e| e.split(';') }].map(&:strip)
      login(config) { |session| command_lines.each { |command| session.cmd(command) } }
    end

    def load(config)
      command_lines = ['', *config.arguments.flat_map { |e| IO.readlines(e) }].map(&:strip)
      login(config) { |session| command_lines.each { |command| session.cmd(command) } }
    end

    private
    def login(config, &block)
      Parallel.map(config.hostlist, in_threads: config.parallel) do |hostinfo|
        begin
          buffer   = StringIO.new
          hostname = hostinfo[:name]

          loggers  = []
          loggers << ((config.parallel > 1)? buffer : $stdout)
          loggers << File.expand_path(File.join(config.logdir, "#{hostname}.log"), ENV['PWD']) if config.logdir

          session = Xlogin.get(hostinfo.merge(log: loggers))
          session.enable if config.enable && hostinfo[:enable]

          block.call(session)
        rescue => e
          lines = (config.parallel > 1)? ["\n#{hostname}\t| [Error] #{e}"] : ["\n[Error] #{e}"]
          lines.each { |line| $stderr.print "#{line.chomp}\n" }
        end

        if config.parallel > 1
          lines = buffer.string.lines.map { |line| "#{hostname}\t| " + line.gsub("\r", '') }
          lines.each { |line| $stdout.print "#{line.chomp}\n" }
        end
      end
    end

  end
end
