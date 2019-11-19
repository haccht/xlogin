#! /usr/bin/env ruby

require 'optparse'
require 'parallel'
require 'stringio'

module Xlogin
  class CLI

    DEFAULT_INVENTORY_FILE = File.join(ENV['HOME'], '.xloginrc')
    DEFAULT_TEMPLATE_DIR   = File.join(ENV['HOME'], '.xlogin.d')

    def self.run(args = ARGV)
      Xlogin::CLI.new.run(args)
    end

    def list(config)
      $stdout.puts Xlogin.list(*config[:pattern]).map { |e| e[:name] }.sort.uniq
    end

    def tty(config)
      info = Xlogin.list(*config[:pattern]).first
      $stdout.puts "Trying #{info[:name]}...", "Escape character is '^]'."

      session, _ = exec(config.merge(pattern: info[:name], jobs: 1))
      session.interact!
    end

    def exec(config)
      Signal.trap(:INT) { exit 0 }

      jobs  = config[:jobs] || 1
      hosts = Xlogin.list(*config[:pattern])
      width = hosts.map { |e| e[:name].length }.max

      Parallel.map(hosts, in_threads: jobs) do |info|
        buffer  = StringIO.new
        prefix  = "#{info[:name].to_s.ljust(width)} |"
        session = nil

        begin
          loggers  = []
          loggers << ((jobs > 1)? buffer : $stdout)
          loggers << File.expand_path(File.join(config[:"log-dir"], "#{info[:name]}.log"), ENV['PWD']) if config[:"log-dir"]

          session = Xlogin.get(info.merge(log: loggers))
          session.enable(info[:enable]) if config[:enable] && info[:enable]

          command_lines = ['', *config[:exec].to_s.split(';').map(&:strip)]
          command_lines.each { |line| session.cmd(line) }

          buffer.string.lines.each { |line| $stdout.print prefix + line.gsub("\r", '') } if jobs > 1
        rescue => e
          buffer.string.lines.each { |line| $stdout.print prefix + line.gsub("\r", '') } if jobs > 1
          raise e
        end

        session
      end
    end

    def run(args)
      config = Hash.new
      config[:runner]    = self.method(:tty)
      config[:inventory] = DEFAULT_INVENTORY_FILE
      config[:template]  = DEFAULT_TEMPLATE_DIR

      parser = OptionParser.new
      parser.banner  = "#{File.basename($0)} HOST_PATTERN [Options]"
      parser.version = Xlogin::VERSION

      parser.on('-i PATH',        '--inventory',    String, 'The PATH to the inventory file (default: $HOME/.xloginrc).')
      parser.on('-T PATH',        '--template',     String, 'The PATH to the template dir (default: $HOME/.xlogin.d).')
      parser.on('-L [DIRECTORY]', '--log-dir',      String, 'The PATH to the log dir (default: $PWD).') { |v| v || '.' }

      parser.on('-t', '--tty',  TrueClass, 'Allocate a pseudo-tty.')  { |v| config[:runner] = self.method(:tty) }
      parser.on('-l', '--list', TrueClass, 'List the inventory.')     { |v| config[:runner] = self.method(:list) }
      parser.on('-e COMMAND', '--exec', 'Execute commands and quit.') { |v| config[:runner] = self.method(:exec); v }

      parser.on('-j NUM', '--jobs', Integer, 'The NUM of jobs to execute in parallel(default: 1).')
      parser.on('-E',     '--enable',     TrueClass, 'Try to gain enable priviledge.')
      parser.on('-y',     '--assume-yes', TrueClass, 'Automatically answer yes to prompts.')

      parser.parse!(args, into: config)
      config[:pattern] = args

      Xlogin.configure do
        set      assume_yes: true if config[:assume_yes]
        source   File.expand_path(config[:inventory], ENV['PWD'])
        template File.expand_path(config[:template],  ENV['PWD'])
      end
      raise "No host found: `#{args.join(', ')}`" if Xlogin.list(*config[:pattern]).empty?

      config[:runner].call(config)
    rescue => e
      $stderr.puts e, '', parser
      exit 1
    end

  end
end
