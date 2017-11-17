require 'uri'
require 'xlogin/ssh'
require 'xlogin/telnet'

module Xlogin
  class Template

    DEFAULT_TIMEOUT  = 10
    DEFAULT_PROMPT   = /[$%#>] ?\z/n
    RESERVED_METHODS = %i( login logout enable delegate )

    attr_reader :name
    attr_reader :methods

    def initialize(name)
      @name    = name
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

    def bind(name = nil, &block)
      @methods[name] = block
    end

    def interrupt(&block)
      return @interrupt unless block
      @interrupt = block
    end

    def build(uri, **params)
      uri   = URI(uri.to_s)
      klass = Class.new(Xlogin.const_get(uri.scheme.capitalize))
      klass.new(self, uri, **params)
    end

    def method_missing(name, *, &block)
      super unless RESERVED_METHODS.include? name
      bind(name) { |*args| instance_exec(*args, &block) }
    end
  end
end
