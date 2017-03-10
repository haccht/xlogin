require 'rspec'
require 'stringio'

require 'xlogin/rspec/context'
require 'xlogin/rspec/resource'

module Xlogin

  module RSpecResourceHelper
    def node(name)
      Resources::NodeResource.new(name)
    end

    def command(str)
      Resources::CommandResource.new(str)
    end

    def backend
      unless @backend
        context = Xlogin::Contexts.from_example(self)
        @backend = context.session if context && context.respond_to?(:session)
      end
      @backend
    end
  end

  module RSpecHelper
    def current_context
      @context
    end

    def method_missing(name, *args, &block)
      if current_context.respond_to?(name)
        current_context.send(name, *args, &block)
      else
        super(name, *args, &block)
      end
    end
  end

end


include Xlogin::RSpecResourceHelper
module RSpec
  Matchers.define :match do |expected|
    match do |actual|
      response = actual.to_s.lines.slice(1..-1).join
      expected =~ response
    end

    failure_message do |actual|
      message = StringIO.new
      message.puts "Expect response to match #{expected.inspect}"
      message.puts "Result:"
      message.puts actual.to_s.lines.slice(1..-2).map { |line| " +#{line}" }
      message.string
    end

    failure_message_when_negated do |actual|
      message = StringIO.new
      message.puts "Expect response not to match #{expected.inspect}"
      message.puts "Result:"
      message.puts actual.to_s.lines.slice(1..-2).map { |line| " +#{line}" }
      message.string
    end
  end

  configure do |config|
    config.include Xlogin::RSpecHelper

    config.before(:all) do
      @context = Xlogin::Contexts.from_example(self.class)
    end

    config.before(:each) do
      @context = Xlogin::Contexts.from_example(RSpec.current_example)
    end
  end
end
