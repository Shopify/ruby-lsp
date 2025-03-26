# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class TestDiscovery
      extend T::Helpers
      abstract!

      include Requests::Support::Common

      DYNAMIC_REFERENCE_MARKER = "<dynamic_reference>"

      #: (ResponseBuilders::TestCollection response_builder, GlobalState global_state, Prism::Dispatcher dispatcher, URI::Generic uri) -> void
      def initialize(response_builder, global_state, dispatcher, uri)
        @response_builder = response_builder
        @uri = uri
        @index = global_state.index #: RubyIndexer::Index
        @visibility_stack = [:public] #: Array[Symbol]
        @nesting = [] #: Array[String]

        dispatcher.register(
          self,
          :on_class_node_leave,
          :on_module_node_enter,
          :on_module_node_leave,
        )
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_enter(node)
        @visibility_stack << :public

        name = constant_name(node.constant_path)
        name ||= name_with_dynamic_reference(node.constant_path)

        @nesting << name
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_leave(node)
        @visibility_stack.pop
        @nesting.pop
      end

      #: (Prism::ClassNode node) -> void
      def on_class_node_leave(node)
        @visibility_stack.pop
        @nesting.pop
      end

      private

      #: (String? name) -> String
      def calc_fully_qualified_name(name)
        RubyIndexer::Index.actual_nesting(@nesting, name).join("::")
      end

      #: (Prism::ClassNode node, String fully_qualified_name) -> Array[String]
      def calc_attached_ancestors(node, fully_qualified_name)
        @index.linearized_ancestors_of(fully_qualified_name)
      rescue RubyIndexer::Index::NonExistingNamespaceError
        # When there are dynamic parts in the constant path, we will not have indexed the namespace. We can still
        # provide test functionality if the class inherits directly from Test::Unit::TestCase or Minitest::Test
        [node.superclass&.slice].compact
      end

      #: (Prism::ConstantPathNode | Prism::ConstantReadNode | Prism::ConstantPathTargetNode | Prism::CallNode | Prism::MissingNode node) -> String
      def name_with_dynamic_reference(node)
        slice = node.slice
        slice.gsub(/((?<=::)|^)[a-z]\w*/, DYNAMIC_REFERENCE_MARKER)
      end

      #: (Prism::ClassNode node, ^(String name, Array[String] ancestors) -> void block) -> void
      def with_test_ancestor_tracking(node, &block)
        @visibility_stack << :public
        name = constant_name(node.constant_path)
        name ||= name_with_dynamic_reference(node.constant_path)

        fully_qualified_name = calc_fully_qualified_name(name)
        attached_ancestors = calc_attached_ancestors(node, fully_qualified_name)

        block.call(fully_qualified_name, attached_ancestors)

        @nesting << name
      end
    end
  end
end
