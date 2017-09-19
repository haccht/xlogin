require 'uri'
require 'xlogin/ssh'
require 'xlogin/telnet'

module Xlogin
  class Firmware

    def initialize
      @timeout = 5
      @cmdhook = nil
      @prompts = Array.new
      @methods = Hash.new
    end

    def timeout(val)
      @timeout = val.to_i
    end

    def hook(&block)
      @cmdhook = block
    end

    def prompt(expect, &block)
      @prompts << [Regexp.new(expect.to_s), block]
    end

    def bind(name, &block)
      @methods[name] = block
    end

    def run(uri, opts = {})
      uri   = URI(uri.to_s)
      klass = Class.new(Xlogin.const_get(uri.scheme.capitalize))
      klass.class_exec(@methods) do |methods|
        methods.each { |m, _| undef_method(m) if method_defined?(m) }
      end

      @methods.each do |name, block|
        klass.class_exec(name, block) do |name, block|
          undef_method(name) if respond_to?(name)
          define_method(name, &block)
        end
      end

      if @cmdhook
        klass.class_exec(@cmdhook) do |cmdhook|
          alias_method :pass, :puts
          define_method(:puts) do |command|
            instance_exec(command, &cmdhook)
          end
        end
      end

      if grant = opts.delete(:grant)
        mod_open, password, mod_close= grant.split(':')
        klass.class_exec(mod_open.to_sym, password, mod_close) do |mod_open, password, mod_close|
          if method_defined?(mod_open)
            alias_method "__#{mod_open}".to_sym, mod_open
            alias_method :enable, mod_open unless mod_open == :enable
          end

          define_method(mod_open) do |*args, &block|
            args = [*args, password] unless password.empty?
            send("__#{mod_open}", *args)
            if block
              block.call
              cmd(mod_close)
            end
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

      session.enable if session.respond_to?(:enable) && opts[:autoenable]
      session
    end

  end
end
