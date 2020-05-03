require 'xlogin/ssh'
require 'xlogin/telnet'

module Xlogin
  class Template

    DEFAULT_TIMEOUT  = 10
    DEFAULT_PROMPT   = /[$%#>] ?\z/n
    RESERVED_METHODS = %i( login logout enable disable )

    attr_reader :name, :methods

    def initialize(name)
      @name    = name
      @prompts = Array.new
      @methods = Hash.new
      @timeout = DEFAULT_TIMEOUT
      @interrupt = nil
    end

    def prompt(expect, &block)
      @prompts << [Regexp.new(expect.to_s), block]
    end

    def prompts
      @prompts << [DEFAULT_PROMPT, nil] if @prompts.empty?
      @prompts
    end

    def bind(name, &block)
      @methods[name] = block
    end

    def timeout(val = nil)
      @timeout = val.to_i if val
      @timeout
    end

    def interrupt!(&block)
      @interrupt = block if block
      @interrupt
    end

    def build(uri, **opts)
      klass = Class.new(Xlogin.const_get(uri.scheme.capitalize))
      klass.class_exec(self) do |template|
        template.methods.each do |name, block|
          define_method(name, &block)
        end
      end

      klass.new(self, uri, **opts)
    end

    def method_missing(name, *, &block)
      super unless RESERVED_METHODS.include?(name)
      bind(name){ |*args| instance_exec(*args, &block) }
    end

  end
end
