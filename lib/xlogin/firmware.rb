require 'uri'
require 'xlogin/ssh'
require 'xlogin/telnet'

module Xlogin
  class Firmware

    def initialize
      @timeout = 5
      @prompts = Array.new

      @hook = nil
      @bind = Hash.new
    end

    def timeout(val)
      @timeout = val.to_i
    end

    def prompt(expect, &block)
      @prompts << [Regexp.new(expect.to_s), block]
    end

    def hook(&block)
      @hook = block
    end

    def bind(name, &block)
      @bind[name] = block
    end

    def run(uri, opts = {})
      uri   = URI(uri.to_s)
      klass = Class.new(Xlogin.const_get(uri.scheme.capitalize))

      @bind.each do |name, block|
        klass.class_exec(name.to_sym, block) do |name, block|
          undef_method(name) if method_defined?(name)
          define_method(name, &block)
        end
      end

      if @hook
        klass.class_exec(@hook) do |cmdhook|
          alias_method :pass, :puts
          define_method(:puts) do |command|
            instance_exec(command, &cmdhook)
          end
        end
      end

      session = klass.new(
        {
          host:     uri.host,
          port:     uri.port,
          userinfo: uri.userinfo,
          timeout:  @timeout,
          prompts:  @prompts,
        }.merge(opts)
      )
    end

  end
end
