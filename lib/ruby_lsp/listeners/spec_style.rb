# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class SpecStyle
      extend T::Sig
      include Requests::Support::Common

      DYNAMIC_REFERENCE_MARKER = "<dynamic_reference>"

      sig do
        params(
          response_builder: ResponseBuilders::TestCollection,
          global_state: GlobalState,
          dispatcher: Prism::Dispatcher,
          uri: URI::Generic,
        ).void
      end
      def initialize(response_builder, global_state, dispatcher, uri)
        @response_builder = response_builder
        @current_group = T.let(nil, T.nilable(Requests::Support::TestItem))
        @uri = uri
        @index = T.let(global_state.index, RubyIndexer::Index)

        @visibility_stack = T.let([:public], T::Array[Symbol])
        @nesting = T.let([], T::Array[String])
        @test_group_nesting = T.let([], T::Array[String])
        @spec_stack = T.let([], T::Array[T::Boolean])

        dispatcher.register(
          self,
          :on_class_node_enter,
          :on_class_node_leave,
          :on_module_node_enter,
          :on_module_node_leave,
          :on_call_node_enter,
          :on_call_node_leave,
          :on_def_node_enter,
        )
      end

      sig { params(node: Prism::ClassNode).void }
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

        @spec_stack.push(attached_ancestors.include?("Minitest::Spec"))

        if attached_ancestors.include?("Minitest::Spec")
          @response_builder.add(Requests::Support::TestItem.new(
            fully_qualified_name,
            fully_qualified_name,
            @uri,
            range_from_node(node),
          ))
        end

        @nesting << name
      end

      sig { params(node: Prism::ModuleNode).void }
      def on_module_node_enter(node)
        @visibility_stack << :public

        name = constant_name(node.constant_path)
        name ||= name_with_dynamic_reference(node.constant_path)

        @nesting << name
      end

      sig { params(node: Prism::ModuleNode).void }
      def on_module_node_leave(node)
        @visibility_stack.pop
        @nesting.pop
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_leave(node)
        @visibility_stack.pop
        @nesting.pop
        @spec_stack.pop
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        case node.name
        when :describe
          description = handle_example_or_group(node)

          @test_group_nesting << description if description
        when :it
          handle_example_or_group(node)
        end
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_leave(node)
        return unless node.name == :describe && !node.receiver

        @test_group_nesting.pop
      end

      sig { params(node: Prism::DefNode).void }
      def on_def_node_enter(node)
        return if @visibility_stack.last != :public
        return unless @spec_stack.last

        name = node.name.to_s
        return unless name.start_with?("test_")

        test_item = current_test_group
        return unless test_item

        test_item.add(Requests::Support::TestItem.new(
          name,
          name,
          @uri,
          range_from_node(node),
        ))
      end

      private

      sig { params(node: Prism::CallNode).returns(T.nilable(String)) }
      def handle_example_or_group(node)
        # Only create a test group if there's a description or a block
        return if node.block.nil?

        first_argument = node.arguments&.arguments&.first
        return unless first_argument

        description = case first_argument
        when Prism::StringNode
          first_argument.content
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          first_argument.slice
        else
          first_argument.slice
        end

        test_item = current_test_group
        return unless test_item

        test_item.add(Requests::Support::TestItem.new(
          description,
          description,
          @uri,
          range_from_node(node),
        ))

        description
      end

      sig do
        params(
          node: T.any(
            Prism::ConstantPathNode,
            Prism::ConstantReadNode,
            Prism::ConstantPathTargetNode,
            Prism::CallNode,
            Prism::MissingNode,
          ),
        ).returns(String)
      end
      def name_with_dynamic_reference(node)
        slice = node.slice
        slice.gsub(/((?<=::)|^)[a-z]\w*/, DYNAMIC_REFERENCE_MARKER)
      end

      sig { returns(T.nilable(Requests::Support::TestItem)) }
      def current_test_group
        current_group_name = RubyIndexer::Index.actual_nesting(@nesting, nil).join("::")

        # If we're finding a test method, but for the wrong framework, then the group test item will not have been
        # previously pushed and thus we return early and avoid adding items for a framework this listener is not
        # interested in
        test_item = T.let(@response_builder[current_group_name], T.nilable(Requests::Support::TestItem))
        return unless test_item

        @test_group_nesting.each do |description|
          test_item = test_item[description]
        end

        test_item
      end
    end
  end
end
