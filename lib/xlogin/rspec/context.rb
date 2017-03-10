module Xlogin
  module Contexts

    class << self
      def from_example(example)
        example_group = example.example_group

        node_resource    = find_resource(Resources::NodeResource, example_group)
        command_resource = find_resource(Resources::CommandResource, example_group)

        return nil if node_resource.nil? && command_resource.nil?
        return NodeContext.new(node_resource.session) if command_resource.nil?

        CommandContext.new(node_resource.session, command_resource.text)
      end

      def find_resource(klass, example_group)
        arg = example_group.metadata[:description_args][0]
        return arg if arg.is_a?(klass)

        parent = example_group.parent_groups[1]
        find_resource(klass, parent) if parent
      end
    end

    class NodeContext
      attr_reader :session

      def initialize(session)
        @session = session
      end

      def name
        @session.name
      end
    end

    class CommandContext
      class << self
        def response_cache
          @cache ||= {}
        end
      end

      attr_reader :session, :command

      def initialize(session, command)
        @session = session
        @command = command 
      end

      def response
        self.class.response_cache[[@session.name, @command]] ||= @session.cmd(@command)
      end
    end

  end
end
