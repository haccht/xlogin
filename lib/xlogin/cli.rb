#! /usr/bin/env ruby

require 'optparse'
require 'readline'
require 'stringio'
require 'thread'

module Xlogin

  class ThreadPool

    def initialize(size)
      @jobs = Array.new
      @lock = Queue.new

      @size = size
      @size.times { @lock.push :token }

      begin yield(self) ensure join end if block_given?
    end

    def run
      @jobs << Thread.new do
        token = @lock.pop
        yield
        @lock.push token
      end
    end

    def join
      @jobs.each { |job| job.join }
    end

  end

  class CLI

    def self.getopts(args)
      options = Hash.new

      opt = OptionParser.new
      opt.on('-e', '--enable', 'Try to gain enable priviledge.') { |v| options[:e] = v }
      opt.on('-l', '--log',    'Enable logging.')                { |v| options[:l] = v }

      opt.on(      '--list',   'List all devices.')              { |v| options[:list] = v }

      opt.banner += ' HOST'
      opt.summary_width = 16

      self.class.module_eval do
        define_method(:usage) do |msg = nil|
          puts opt.to_s
          puts "error: #{msg}" if msg
          exit 1
        end
      end

      opt.parse!(args)
      return options, args
    end

    def self.run(args = ARGV)
      options, args = getopts(args)

      if options[:list]
        puts Xlogin.factory.list.map { |e| "#{e[:name]}\t#{e[:type]}" }
        exit 0
      end

      target = args.shift
      usage unless target

      loggers = [$stdout]
      loggers.push("#{target}.log") if options[:l]

      puts "Trying #{target}..."
      puts "Escape character is '^]'."

      session = Xlogin.get(target, force_grant: options[:e], log: loggers)
      session.interact!
    rescue => e
      $stderr.puts("#{e}\n\n")
      raise
    end

  end

  class ExecCLI

    def self.getopts(args)
      options = Hash.new

      opt = OptionParser.new
      opt.on('-F', '--force',  'Automatically reply "yes" if confirmed.') { |v| options[:F] = v }
      opt.on('-e', '--enable', 'Try to gain enable priviledge.')          { |v| options[:e] = v }
      opt.on('-l', '--log',    'Enable logging.')                         { |v| options[:l] = v }
      opt.on('-H', 'Display hostnames for each response.')   { |v| options[:H] = v }

      opt.on('-f FILE',  'Read target hostnames from FILE.') { |v| options[:f] = v }

      opt.on('-x VALUE', 'Read commands from VALUE.')        { |v| options[:x] = v }
      opt.on('-c VALUE')                                     { |v| options[:c] = v }

      opt.on('-p VALUE', 'Specify concurrency pool size.')   { |v| options[:p] = v }
      opt.on('-i VALUE', 'Specify interval time [sec].')     { |v| options[:i] = v }

      opt.banner += ' HOST...'
      opt.summary_width = 16

      self.class.module_eval do
        define_method(:usage) do |msg = nil|
          puts opt.to_s
          puts "error: #{msg}" if msg
          exit 1
        end
      end

      opt.parse!(args)
      return options, args
    end

    def self.run(args = ARGV)
      options, args = getopts(args)
      usage if options[:x].nil? and options[:c].nil?
      usage if options[:f].nil? && args.empty?

      size     = (options[:p] || 1).to_i
      interval = (options[:i] || 0).to_i
      commands = ((options[:x] == '-') ? $stdin.read : options[:x]).split(/[;\n]/) if options[:x]

      nodes  = args.dup
      nodes += IO.readlines(options[:f]).map(&:chomp) if options[:f]

      ThreadPool.new(size) do |pool|
        nodes.each do |node|
          next if node =~ /^\s*#/

          pool.run do
            begin
              resp    = StringIO.new
              force   = options[:F] || false
              loggers = []
              loggers << $stdout unless size > 1
              loggers << (URI.regexp =~ node ? URI(node).host : node) + ".log" if options[:l]


              session = Xlogin.get(node, force: force, log: loggers)
              session.enable if options[:e] && session.respond_to?(:enable)

              if options[:x]
                ['', *commands].map { |command| resp.print session.cmd(command) }
              elsif options[:c]
                resp.puts session.send(options[:c].to_sym)
              end

              content = resp.string
              content = content.lines.map { |line| "#{node}: #{line}" }.join if options[:H]

              $stdout.puts content if size > 1
            rescue => e
              $stderr.puts "Something goes wrong with '#{node}' - #{e}"
            end
          end
        end
      end
    end
  end
end
