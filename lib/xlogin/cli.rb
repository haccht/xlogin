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
      client.method(config.taskname).call(config)
    end

    def self.getopts(args)
      config = OpenStruct.new(
        jobs: 1,
        port: 8080,
        taskname: :tty,
        inventory: nil,
        templates: [],
      )

      parser = OptionParser.new
      parser.banner  = "#{File.basename($0)} HOST_PATTERN [Options]"
      parser.version = Xlogin::VERSION

      parser.on('-i PATH',        '--inventory',    String, 'The PATH to the inventory file(default: $HOME/.xloginrc).') { |v| config.inventory = v }
      parser.on('-t PATH',        '--template',     String, 'The PATH to the template file.') { |v| config.templates << v }
      parser.on('-T DIRECTORY',   '--template-dir', String, 'The DIRECTORY of the template files.') { |v| config.templates += Dir.glob(File.join(v, '*.rb')) }
      parser.on('-L [DIRECTORY]', '--log-dir',      String, 'The DIRECTORY of the log files(default: $PWD).') { |v| config.logdir = v || '.' }

      parser.on('-l', '--list', TrueClass, 'List all available devices.') { |v| config.taskname = :list }
      parser.on('-e', '--exec', TrueClass, 'Execute commands and quit.') { |v| config.taskname = :exec }
      parser.on('-t', '--tty',  TrueClass, 'Allocate a pseudo-tty.') { |v| config.taskname = :tty }

      parser.on('-p NUM', '--port', Integer, 'Run as server on specified port(default: 8080).') { |v| config.taskname = :listen; config.port = v }
      parser.on('-j NUM', '--jobs', Integer, 'The NUM of jobs to execute in parallel(default: 1).') { |v| config.jobs = v }

      parser.on('-E',     '--enable',     TrueClass, 'Try to gain enable priviledge.') { |v| config.enable = v }
      parser.on('-y',     '--assume-yes', TrueClass, 'Automatically answer yes to prompts.') { |v| config.authorize = v }

      begin
        args = parser.parse!(args)
        host = args.shift
        config.args = args

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

        config.hostlist  = host.to_s.split(/\s+/).map { |pattern| Xlogin.factory.list(pattern) }.reduce(&:&)
        raise "No host found: `#{host}`" if config.hostlist.empty?
      rescue => e
        $stderr.puts e, '', parser
        exit 1
      end

      config
    end

    def list(config)
      wid1 = config.hostlist.map { |e| e[:name].length }.max
      wid2 = config.hostlist.map { |e| e[:type].length }.max
      list = config.hostlist.map { |e| "#{e[:name].to_s.ljust(wid1)} #{e[:type].to_s.ljust(wid2)} #{e[:uri]}" }.sort
      $stdout.puts list
    end

    def tty(config)
      Signal.trap(:INT) { exit 0 }

      list = config.hostlist.sort_by { |e| e[:name] }
      list.each do |target|
        unless list.size == 1
          case resp = Readline.readline(">> #{target[:name]}(Y/n)? ", false).strip
          when /^y(es)?$/i, ''
          when /^n(o)?$/i then next
          else redo
          end
        end

        config.jobs = 1
        config.hostlist = [target]

        $stdout.puts "Trying #{target[:name]}...", "Escape character is '^]'."
        session, _ = exec(config)
        session.interact!
      end
    end

    def listen(config)
      Signal.trap(:INT) { exit 0 }
      config.jobs = config.hostlist.size

      width    = config.hostlist.map { |e| e[:name].length }.max
      sessions = exec(config).compact

      $stdout.puts "", ""
      $stdout.puts "=> Start xlogin server on port=#{config.port}"
      $stdout.puts "=> Ctrl-C to shutdown"

      server = TCPServer.open(config.port)
      socket = server.accept
      while line = socket.gets
        Parallel.each(sessions, in_threads: sessions.size) do |session|
          resp   = session.cmd(line.chomp)
          prefix = "#{session.name.to_s.ljust(width)} |"
          output = resp.to_s.lines.map { |line| prefix + line.chomp.gsub("\r", '') + "\n" }.join
          socket.print  output
          $stdout.print output if config.jobs > 1
        end
      end
    ensure
      socket.close if socket
      server.close if server
    end

    def exec(config, &block)
      width = config.hostlist.map { |e| e[:name].length }.max

      Parallel.map(config.hostlist, in_threads: config.jobs) do |hostinfo|
        session = nil
        error   = nil

        begin
          buffer   = StringIO.new
          hostname = hostinfo[:name]

          loggers  = []
          loggers << ((config.jobs > 1)? buffer : $stdout)
          loggers << File.expand_path(File.join(config.logdir, "#{hostname}.log"), ENV['PWD']) if config.logdir

          session = Xlogin.get(hostinfo.merge(log: loggers))
          session.enable if config.enable && hostinfo[:enable]

          command_lines = ['', *config.args.flat_map { |e| e.split(';') }].map(&:strip)
          command_lines.each { |line| session.cmd(line) }

          block.call(session) if block
        rescue => e
          error = e
        ensure
          if config.jobs > 1
            prefix = "#{hostname.to_s.ljust(width)} |"
            output = buffer.string.lines.map { |line| prefix + line.chomp.gsub("\r", '') + "\n" }.join
            $stdout.print output
            $stderr.print prefix + "[Error] #{error}\n" if error
          else
            $stderr.print "[Error] #{error}\n" if error
          end

        end

        session
      end
    end

  end
end
