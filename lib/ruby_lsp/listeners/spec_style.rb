# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class SpecStyle
      extend T::Sig
      include Requests::Support::Common

      DYNAMIC_REFERENCE_MARKER = "<dynamic_reference>"

      #: (response_builder: ResponseBuilders::TestCollection, global_state: GlobalState, dispatcher: Prism::Dispatcher, uri: URI::Generic) -> void
      def initialize(response_builder, global_state, dispatcher, uri)
        @response_builder = response_builder
        @uri = uri
        @index = T.let(global_state.index, RubyIndexer::Index)
        @visibility_stack = T.let([:public], T::Array[Symbol])
        @nesting = T.let([], T::Array[String])
        @describe_block_nesting = T.let([], T::Array[String])
        @spec_class_stack = T.let([], T::Array[T::Boolean])

        dispatcher.register(
          self,
          :on_class_node_enter,
          :on_class_node_leave,
          :on_module_node_enter,
          :on_module_node_leave,
          :on_call_node_enter, # e.g. `describe` or `it`
          :on_call_node_leave,
        )
      end

      #: (node: Prism::ClassNode) -> void
      def on_class_node_enter(node)
        @visibility_stack << :public
        name = constant_name(node.constant_path)
        name ||= name_with_dynamic_reference(node.constant_path)

        fully_qualified_name = RubyIndexer::Index.actual_nesting(@nesting, name).join("::")

        attached_ancestors = begin
          @index.linearized_ancestors_of(fully_qualified_name)
        rescue RubyIndexer::Index::NonExistingNamespaceError
          # When there are dynamic parts in the constant path, we will not have indexed the namespace. We can still
          # provide test functionality if the class inherits directly from Test::Unit::TestCase or Minitest::Test
          [node.superclass&.slice].compact
        end

        is_spec = attached_ancestors.include?("Minitest::Spec")
        @spec_class_stack.push(is_spec)

        @nesting << name
      end

      #: (node: Prism::ModuleNode) -> void
      def on_module_node_enter(node)
        @visibility_stack << :public

        name = constant_name(node.constant_path)
        name ||= name_with_dynamic_reference(node.constant_path)

        @nesting << name
      end

      #: (node: Prism::ModuleNode) -> void
      def on_module_node_leave(node)
        @visibility_stack.pop
        @nesting.pop
      end

      #: (node: Prism::ClassNode) -> void
      def on_class_node_leave(node)
        @visibility_stack.pop
        @nesting.pop
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
            tags: [:minitest],
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
          tags: [:minitest],
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

        test_group = T.let(@response_builder[root_group_name], T.nilable(Requests::Support::TestItem))
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

        T.must(@spec_class_stack.last)
      end

      #: (node: Prism::ConstantPathNode | Prism::ConstantReadNode | Prism::ConstantPathTargetNode | Prism::CallNode | Prism::MissingNode) -> String
      def name_with_dynamic_reference(node)
        slice = node.slice
        slice.gsub(/((?<=::)|^)[a-z]\w*/, DYNAMIC_REFERENCE_MARKER)
      end
    end
  end
end
