require 'xlogin'
require 'xlogin/thread_safe'

module Xlogin

  class Scanner
    class << self
      def login_opts(**opts)
        @login_opts = opts unless opts.empty?
        @login_opts || {}
      end
    end

    def initialize
      @sessions = Hash.new
      @scan_db  = Hash.new
      @queries  = Array.new
    end

    def ids
      @scan_db.keys
    end

    def define(id, &block)
      type = ScanType.new
      type.instance_eval(&block)

      @scan_db[id] = type
    end

    def add(id, hostname, *args)
      @queries << [id, hostname, *args]
    end

    def scan
      data  = Hash.new
      cache = Hash.new

      threads = @queries.map do |req_key|
        Thread.new do
          id, hostname, *args = *req_key
          type = @scan_db[id]

          command = type.command.call(*args)
          content = session(hostname).thread_safe { |s| s.cmd(command) }
          matched = type.scanner.call(content)

          cache[[hostname, command]] ||= content
          data[req_key] = matched

          yield(req_key, matched) if block_given?
        end
      end
      threads.each { |th| th.join }

      data
    end

    def close
      @sessions.each { |_, s| s.close }
    end

    private
    def session(hostname)
      @sessions[hostname] ||= Xlogin.get(hostname, **Xlogin::Scanner.login_opts)
    end
  end

  class ScanType
    def command(val = nil, &block)
      return @command unless val || block
      @command = (val) ? lambda { val } : block
    end

    def scanner(&block)
      return @scanner unless block
      @scanner = block
    end
  end

end
