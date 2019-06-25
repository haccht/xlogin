require 'xlogin/ssh'
require 'xlogin/telnet'

module Xlogin
  class Template

    DEFAULT_TIMEOUT  = 10
    DEFAULT_PROMPT   = /[$%#>] ?\z/n
    RESERVED_METHODS = %i( login logout enable disable delegate )

    attr_reader :name

    def initialize(name)
      @name    = name
      @timeout = DEFAULT_TIMEOUT
      @prompts = Array.new
      @methods = Hash.new { |h, k| h[k] = {} }
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

    def bind(name = nil, scope: :default, &block)
      @methods[scope][name] = block
    end

    def interrupt!(&block)
      return @interrupt unless block
      @interrupt = block
    end

    def build(uri, **opts)
      klass = Class.new(Xlogin.const_get(uri.scheme.capitalize))
      klass.class_exec(@methods) do |methods|
        [:default, *opts[:scope]].uniq.each do |scope|
          methods[scope].each do |name, block|
            case name.to_s
            when 'enable'
              define_method(name) { |args = nil| instance_exec(args || opts[:enable], &block) }
            else
              define_method(name, &block)
            end
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
