module Xlogin
  module Resources

    class NodeResource
      def initialize(name)
        @name = name
      end

      def session
        @session ||= Xlogin.get(@name)
      end

      def to_s
        "Node '#{session.name}'"
      end
    end

    class CommandResource
      attr_reader :text

      def initialize(text)
        @text = text
      end

      def to_s
        "with command '#{text}'"
      end
    end

  end
end
