require 'optparse'
require 'parallel'
require 'stringio'

module Xlogin
  class CLI

    DEFAULT_INVENTORY = File.join(ENV['HOME'], '.xloginrc')
    DEFAULT_TEMPLATE  = File.join(ENV['HOME'], '.xlogin.d')

    def self.run(args = ARGV)
      Xlogin::CLI.new.run(args)
    end

    def list(config)
      puts Xlogin.list(*config[:patterns]).map{ |e| e[:name] }.sort.uniq
    end

    def tty(config)
      info = Xlogin.find(*config[:patterns])
      puts "Trying #{info[:name]}...", "Escape character is '^]'."

      session, _ = exec(config.merge(patterns: info[:name], jobs: 1))
      session.interact!
    end

    def exec(config)
      Signal.trap(:INT){ exit 1 }

      jobs  = config[:jobs] || 1
      hosts = Xlogin.list(*config[:patterns])
      width = hosts.map{ |e| e[:name].length }.max
      raise "No host found: `#{config[:patterns].join(', ')}`" if hosts.empty?

      Parallel.map(hosts, in_threads: jobs) do |info|
        buffer  = StringIO.new
        prefix  = "#{info[:name].to_s.ljust(width)} |"
        session = nil

        begin
          loggers  = []
          loggers << ((jobs > 1)? buffer : $stdout)
          loggers << File.expand_path(File.join(config[:logdir], "#{info[:name]}.log"), ENV['PWD']) if config[:logdir]

          session = Xlogin.get(info.merge(log: loggers))
          session.enable(session.config.enable) if session.config.enable && Xlogin.settings.enable?

          command_lines = config[:command].flat_map { |e| e.to_s.split(';').map(&:strip) }
          command_lines.each{ |line| session.cmd(line) }

          buffer.string.lines.each{ |line| print prefix + line.gsub(/^.*\r/, '') } if jobs > 1
        rescue => e
          buffer.string.lines.each{ |line| print prefix + line.gsub(/^.*\r/, '') } if jobs > 1
          raise e
        end

        session
      end
    end

    def run(args)
      config = Hash.new
      config[:env]       = []
      config[:inventory] = []
      config[:template]  = []
      config[:command]   = []
      config[:runner]    = self.method(:tty)

      parser = OptionParser.new
      parser.banner  = "#{File.basename($0)} HOST_PATTERN [Options]"
      parser.version = Xlogin::VERSION

      parser.on('-i PATH', '--inventory', String, 'The PATH to the inventory file.')            { |v| config[:inventory] << v }
      parser.on('-t PATH', '--template',  String, 'The PATH to the template file or directory.'){ |v| config[:template]  << v }
      parser.on('-L PATH', '--log-dir',   String, 'The PATH to the log directory.')             { |v| config[:logdir]     = v }

      parser.on('-l',         '--list',   TrueClass, 'List the inventory.')       { |v| config[:runner] = self.method(:list) }
      parser.on('-e COMMAND', '--exec',   String,    'Execute commands and quit.'){ |v| config[:runner] = self.method(:exec); config[:command] << v }

      parser.on('-E KEY=VAL', '--env',    /(\w+=\w+)+/, 'Environment variables.')                 { |v| config[:env] << v }
      parser.on('-j NUM',     '--jobs',   Integer,      'The NUM of jobs to execute in parallel.'){ |v| config[:jobs] = v }

      config[:patterns]  = parser.parse!(args)
      config[:inventory] << DEFAULT_INVENTORY if config[:inventory].empty?
      config[:template]  << DEFAULT_TEMPLATE  if config[:template].empty?

      Xlogin.configure do
        set Hash[config[:env].map{ |v| v.split('=') }]

        source   *config[:inventory].map{ |e| File.expand_path(e, ENV['PWD']) }
        template *config[:template].map { |e| File.expand_path(e, ENV['PWD']) }
      end

      raise Xlogin::Error.new("Invalid host pattern: '#{config[:patterns].join(' ')}'") if Xlogin.list(*config[:patterns]).empty?
      config[:runner].call(config)
    rescue => e
      $stderr.puts e, '', parser
      exit 1
    end

  end
end
