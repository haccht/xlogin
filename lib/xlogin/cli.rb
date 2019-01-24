#! /usr/bin/env ruby

require 'optparse'
require 'ostruct'
require 'parallel'
require 'readline'
require 'socket'
require 'stringio'

module Xlogin
  class CLI

    DEFAULT_INVENTORY_FILE = File.join(ENV['HOME'], '.xloginrc')
    DEFAULT_TEMPLATE_DIR   = File.join(ENV['HOME'], '.xlogin.d')

    def self.run(args = ARGV)
      config = getopts(args)
      client = Xlogin::CLI.new
			client.method(config.task.first).call(config)
    end

    def self.getopts(args)
      config = OpenStruct.new(
				jobs: 1,
				auth: false,
				task: [:tty, nil],
				inventory:    DEFAULT_INVENTORY_FILE,
				template_dir: DEFAULT_TEMPLATE_DIR,
			)

      parser = OptionParser.new
      parser.banner  = "#{File.basename($0)} HOST_PATTERN [Options]"
      parser.version = Xlogin::VERSION

      parser.on('-i PATH',        '--inventory',    String, 'The PATH to the inventory file (default: $HOME/.xloginrc).') { |v| config.inventory    = v }
			parser.on('-T PATH',        '--template',     String, 'The PATH to the template dir (default: $HOME/.xlogin.d).')   { |v| config.template_dir = v }
			parser.on('-L [DIRECTORY]', '--log-dir',      String, 'The PATH to the log dir (default: $PWD).')                   { |v| config.logdir = v || '.' }

      parser.on('-l', '--list', TrueClass, 'List the inventory.')    { |v| config.task = [:list, nil] }
      parser.on('-t', '--tty',  TrueClass, 'Allocate a pseudo-tty.') { |v| config.task = [:tty,  nil] }
      parser.on('-e COMMAND', '--exec', TrueClass, 'Execute commands and quit.') { |v| config.task = [:exec, v] }

      parser.on('-j NUM', '--jobs', Integer, 'The NUM of jobs to execute in parallel(default: 1).') { |v| config.jobs = v }
      parser.on('-y',     '--assume-yes', TrueClass, 'Automatically answer yes to prompts.')        { |v| config.auth = v }
      parser.on('-E',     '--enable',     TrueClass, 'Try to gain enable priviledge.')              { |v| config.enable = v }

			parser.parse!(args)

			config.hosts = Xlogin.list(*args)
			raise "No host found: `#{args}`" if config.hosts.empty?

			Xlogin.configure do
				authorize(config.auth)
				source(File.expand_path(config.inventory, ENV['PWD']))
				template_dir(File.expand_path(config.template_dir, ENV['PWD']))
			end

      return config
		rescue => e
			$stderr.puts e, '', parser
			exit 1
    end

    def list(config)
      $stdout.puts config.hosts.map { |e| e[:name] }.sort.uniq
    end

    def tty(config)
      Signal.trap(:INT) { exit 0 }

			config.hosts.each do |hostinfo|
				unless config.hosts.size == 1
          case resp = Readline.readline(">> #{hostinfo[:name]}(Y/n)? ", false).strip
          when /^y(es)?$/i, ''
          when /^n(o)?$/i then next
          else redo
          end
        end

				# rewrite config in order to process hosts one by one
        $stdout.puts "Trying #{hostinfo[:name]}...", "Escape character is '^]'."
        config.jobs = 1
        config.hosts = [hostinfo]

        session, _ = exec(config)
        session.interact!
      end
    end

    def exec(config)
      Signal.trap(:INT) { exit 0 }

      max_width = config.hosts.map { |e| e[:name].length }.max
      Parallel.map(config.hosts, in_threads: config.jobs) do |hostinfo|
        session = nil
        error   = nil

        begin
          buffer   = StringIO.new

          loggers  = []
          loggers << ((config.jobs > 1)? buffer : $stdout)
          loggers << File.expand_path(File.join(config.logdir, "#{hostinfo[:name]}.log"), ENV['PWD']) if config.logdir

          session = Xlogin.get(hostinfo.merge(log: loggers))
          session.enable if config.enable && hostinfo[:enable]

					command_lines = ['', *config.task.last.split(';').map(&:strip)]
          command_lines.each { |line| session.cmd(line) }
        rescue => err
          error = err
				end

				if config.jobs > 1
					prefix = "#{hostinfo[:name].to_s.ljust(max_width)} |"
					output = buffer.string.lines.map { |line| prefix + line.chomp.gsub("\r", '') + "\n" }.join
					$stdout.print output
					$stderr.print prefix + "[Error] #{error}\n" if error
				else
					$stderr.print "[Error] #{error}\n" if error
				end

        session
      end
    end

  end
end
