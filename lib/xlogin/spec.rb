module Xlogin

  class ExpectationError < StandardError

    def initialize(expect, actual)
      super("Expected to match #{expect}")
      @actual = actual
    end

    def full_message
      "#{message},\nbut actually was:\n#{@actual}"
    end

  end

  class Expectation

    def initialize(session, *args)
      @session = session
      @args = args
    end

    def to_match(regexp)
      return if match(regexp)
      raise ExpectationError.new(@expect, @actual)
    end

    def not_to_match(regexp)
      return unless match(regexp)
      raise ExpectationError.new(@expect, @actual)
    end

    private
    def match(regexp)
      regexp  = Regexp.new(regexp.to_s) unless regexp.kind_of?(Regexp)
      @expect = regexp.inspect

      @actual || = @session.cmd(*@args)
      @actual =~ regexp
    end

  end

  module SessionModule

    def expect(*args)
      Expectation.new(self, *args)
    end

  end

end
