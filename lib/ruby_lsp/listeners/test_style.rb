# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class TestStyle
      extend T::Sig
      include Requests::Support::Common

      ACCESS_MODIFIERS = [:public, :private, :protected].freeze
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
        @uri = uri
        @index = T.let(global_state.index, RubyIndexer::Index)
        @visibility_stack = T.let([:public], T::Array[Symbol])
        @nesting = T.let([], T::Array[String])

        dispatcher.register(
          self,
          :on_class_node_enter,
          :on_class_node_leave,
          :on_module_node_enter,
          :on_module_node_leave,
          :on_def_node_enter,
          :on_call_node_enter,
          :on_call_node_leave,
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

        if attached_ancestors.include?("Test::Unit::TestCase") ||
            non_declarative_minitest?(attached_ancestors, fully_qualified_name)

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
      end

      sig { params(node: Prism::DefNode).void }
      def on_def_node_enter(node)
        return if @visibility_stack.last != :public

        name = node.name.to_s
        return unless name.start_with?("test_")

        current_group_name = RubyIndexer::Index.actual_nesting(@nesting, nil).join("::")

        # If we're finding a test method, but for the wrong framework, then the group test item will not have been
        # previously pushed and thus we return early and avoid adding items for a framework this listener is not
        # interested in
        test_item = @response_builder[current_group_name]
        return unless test_item

        test_item.add(Requests::Support::TestItem.new(
          "#{current_group_name}##{name}",
          name,
          @uri,
          range_from_node(node),
        ))
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        name = node.name
        return unless ACCESS_MODIFIERS.include?(name)

        @visibility_stack << name
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_leave(node)
        name = node.name
        return unless ACCESS_MODIFIERS.include?(name)
        return unless node.arguments&.arguments

        @visibility_stack.pop
      end

      private

      sig { params(attached_ancestors: T::Array[String], fully_qualified_name: String).returns(T::Boolean) }
      def non_declarative_minitest?(attached_ancestors, fully_qualified_name)
        return false unless attached_ancestors.include?("Minitest::Test")

        # We only support regular Minitest tests. The declarative syntax provided by ActiveSupport is handled by the
        # Rails add-on
        name_parts = fully_qualified_name.split("::")
        singleton_name = "#{name_parts.join("::")}::<Class:#{name_parts.last}>"
        !@index.linearized_ancestors_of(singleton_name).include?("ActiveSupport::Testing::Declarative")
      rescue RubyIndexer::Index::NonExistingNamespaceError
        true
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
    end
  end
end
