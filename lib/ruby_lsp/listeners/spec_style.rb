# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class SpecStyle < TestDiscovery
      extend T::Sig

      #: (response_builder: ResponseBuilders::TestCollection, global_state: GlobalState, dispatcher: Prism::Dispatcher, uri: URI::Generic) -> void
      def initialize(response_builder, global_state, dispatcher, uri)
        super

        @describe_block_nesting = [] #: Array[String]
        @spec_class_stack = [] #: Array[bool]

        dispatcher.register(
          self,
          # Common handlers registered in parent class
          :on_class_node_enter,
          :on_call_node_enter, # e.g. `describe` or `it`
          :on_call_node_leave,
        )
      end

      #: (node: Prism::ClassNode) -> void
      def on_class_node_enter(node)
        with_test_ancestor_tracking(node) do |_, ancestors|
          is_spec = ancestors.include?("Minitest::Spec")
          @spec_class_stack.push(is_spec)
        end
      end

      #: (node: Prism::ClassNode) -> void
      def on_class_node_leave(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        super

        @spec_class_stack.pop
      end

      #: (node: Prism::CallNode) -> void
      def on_call_node_enter(node)
        case node.name
        when :describe
          handle_describe(node)
        when :it, :specify
          handle_example(node)
        end
      end

      #: (node: Prism::CallNode) -> void
      def on_call_node_leave(node)
        return unless node.name == :describe && !node.receiver

        @describe_block_nesting.pop
      end

      private

      #: (node: Prism::CallNode) -> void
      def handle_describe(node)
        return if node.block.nil?

        description = extract_description(node)
        return unless description

        return unless in_spec_context?

        if @nesting.empty? && @describe_block_nesting.empty?
          test_item = Requests::Support::TestItem.new(
            description,
            description,
            @uri,
            range_from_node(node),
            framework: :minitest,
          )
          @response_builder.add(test_item)
        else
          add_to_parent_test_group(description, node)
        end

        @describe_block_nesting << description
      end

      #: (node: Prism::CallNode) -> void
      def handle_example(node)
        return unless in_spec_context?

        return if @describe_block_nesting.empty? && @nesting.empty?

        description = extract_description(node)
        return unless description

        add_to_parent_test_group(description, node)
      end

      #: (description: String, node: Prism::CallNode) -> void
      def add_to_parent_test_group(description, node)
        parent_test_group = find_parent_test_group
        return unless parent_test_group

        test_item = Requests::Support::TestItem.new(
          description,
          description,
          @uri,
          range_from_node(node),
          framework: :minitest,
        )
        parent_test_group.add(test_item)
      end

      #: -> Requests::Support::TestItem?
      def find_parent_test_group
        root_group_name, nested_describe_groups = if @nesting.empty?
          [@describe_block_nesting.first, @describe_block_nesting[1..]]
        else
          [RubyIndexer::Index.actual_nesting(@nesting, nil).join("::"), @describe_block_nesting]
        end
        return unless root_group_name

        test_group = @response_builder[root_group_name] #: Requests::Support::TestItem?
        return unless test_group

        return test_group unless nested_describe_groups

        nested_describe_groups.each do |description|
          test_group = test_group[description]
        end

        test_group
      end

      #: (node: Prism::CallNode) -> String?
      def extract_description(node)
        first_argument = node.arguments&.arguments&.first
        return unless first_argument

        case first_argument
        when Prism::StringNode
          first_argument.content
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          constant_name(first_argument)
        else
          first_argument.slice
        end
      end

      #: -> bool
      def in_spec_context?
        return true if @nesting.empty?

        @spec_class_stack.last #: as !nil
      end
    end
  end
end
