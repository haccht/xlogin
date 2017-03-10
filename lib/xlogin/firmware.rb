require 'uri'
require 'xlogin/telnet'

module Xlogin
  class Firmware

    def initialize
      @timeout = 5
      @on_exec  = nil
      @prompts = Array.new
      @methods = Hash.new
    end

    def timeout(val)
      @timeout = val.to_i
    end

    def on_exec(&block)
      @on_exec = block
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

      if @on_exec
        klass.class_exec(@on_exec) do |on_exec|
          alias_method :do_cmd, :cmd
          define_method(:cmd) do |args|
            args = {'String' => args.to_s} unless args.kind_of?(Hash)
            instance_exec(args, &on_exec)
          end
        end
      end

      if enable = opts.delete(:enable)
        name, password = ['enable', *enable.split(':')][-2..-1]
        klass.class_exec(name, password) do |name, password|
          alias_method "original_#{name}".to_sym, name.to_sym
          define_method(:enable) do |args = password|
            send("original_#{name}", args)
          end
        end
      end

      klass.new(
        {
          node:     uri.host,
          port:     uri.port,
          userinfo: uri.userinfo,
          timeout:  @timeout,
          prompts:  @prompts,
          methods:  @methods,
        }.merge(opts)
      )
    end

  end
end
