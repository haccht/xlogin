require 'json'
require 'ostruct'
require 'xlogin'

module Xlogin

  class Request
    class << self
      def login_opts(**opts)
        Xlogin::Queue.login_opts(opts)
      end
    end

    def initialize
      @database = Hash.new
      @requests = Array.new

      @cache = nil
    end

    def keys
      @database.keys
    end

    def define(key, &block)
      type = RequestType.new
      type.instance_eval(&block)

      @database[key] = type
    end

    def query(key, hostname, *args)
      @requests << [key, hostname, *args]
    end

    def execute
      data  = Hash.new
      cache = Hash.new

      threads = @requests.map do |req_key|
        Thread.new do
          key, hostname, *args = *req_key
          type = @database[key]

          command = type.command.call(*args)
          content = cache[[hostname, command]] ||= exec(hostname, command)
          matched = type.scanner.call(content)

          data[req_key] = matched
          yield(req_key, matched) if block_given?
        end
      end
      threads.each { |th| th.join }

      data
    end

    def close
      hostnames = @requests.map { |_, hostname, _| hostname }.uniq
      hostnames.each do |hostname|
        queue = Xlogin::Queue.get(hostname)
        queue.raw_session.cmd('exit')
      end
    end

    private
    def exec(hostname, command)
      queue = Xlogin::Queue.get(hostname)
      queue.with(timeout: 5) do |session|
        session.cmd(command)
      end
    end
  end

  class RequestType
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
