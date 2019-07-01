require 'xlogin/ssh'
require 'xlogin/telnet'

module Xlogin
  class Template

    DEFAULT_TIMEOUT  = 10
    DEFAULT_PROMPT   = /[$%#>] ?\z/n
    RESERVED_METHODS = %i( login logout enable disable delegate )

    attr_reader :name, :scopes, :methods

    def initialize(name)
      @name    = name
      @scopes  = Hash.new
      @timeout = DEFAULT_TIMEOUT
      @prompts = Array.new
      @methods = Hash.new
      @interrupt = nil
    end

    def timeout(val = nil)
      @timeout = val.to_i if val
      @timeout
    end

    def prompt(expect = nil, &block)
      return [[DEFAULT_PROMPT, nil]] if expect.nil? && @prompts.empty?
      @prompts << [Regexp.new(expect.to_s), block] if expect
      @prompts
    end

    def scope(name = nil, &block)
      @scopes[name] = block
    end

    def bind(name = nil, &block)
      @methods[name] = block
    end

    def interrupt!(&block)
      return @interrupt unless block
      @interrupt = block
    end

    def build(uri, **opts)
      klass = Class.new(Xlogin.const_get(uri.scheme.capitalize))
      klass.class_exec(self) do |template|
        scopes = [*opts[:scope]].compact
        scopes.each { |scope| template.instance_eval(&template.scopes[scope]) }

        template.methods.each do |name, block|
          case name.to_s
          when 'enable'
            define_method(name) { |args = nil| instance_exec(args || opts[:enable], &block) }
          else
            define_method(name, &block)
          end
        end
      end

      klass.new(self, uri, **opts)
    end

    def method_missing(name, *, &block)
      super unless RESERVED_METHODS.include?(name)
      bind(name) { |*args| instance_exec(*args, &block) }
    end

  end
end
