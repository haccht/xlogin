module Xlogin
  class ExpectationError < StandardError

    def initialize(expect, actual)
      super(expect)
      @actual = actual
    end

    def full_message
      "#{message},\nbut actually was:\n#{@actual}"
    end

  end

  class Expectation

    def initialize(result)
      @result = result
    end

    def to_match(regexp)
      regexp = Regexp.new(regexp.to_s) unless regexp.kind_of?(Regexp)
      return if @result =~ regexp

      raise ExpectationError.new("Expected to match #{regexp}", @result)
    end

    def not_to_match(regexp)
      regexp = Regexp.new(regexp.to_s) unless regexp.kind_of?(Regexp)
      return if @result !~ regexp

      raise ExpectationError.new("Expected not to match #{regexp}", @result)
    end

  end

  module SessionModule

    def expect(*args)
      Expectation.new(cmd(*args))
    end

  end
end
