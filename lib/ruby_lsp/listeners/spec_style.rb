# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class SpecStyle < TestDiscovery
      class Group
        #: String
        attr_reader :id

        #: (String) -> void
        def initialize(id)
          @id = id
        end
      end

      class ClassGroup < Group; end
      class DescribeGroup < Group; end

      #: (ResponseBuilders::TestCollection, GlobalState, Prism::Dispatcher, URI::Generic) -> void
      def initialize(response_builder, global_state, dispatcher, uri)
        super

        @spec_group_id_stack = [] #: Array[Group?]

        dispatcher.register(
          self,
          # Common handlers registered in parent class
          :on_class_node_enter,
          :on_call_node_enter, # e.g. `describe` or `it`
          :on_call_node_leave,
        )
      end

      #: (Prism::ClassNode) -> void
      def on_class_node_enter(node)
        with_test_ancestor_tracking(node) do |name, ancestors|
          @spec_group_id_stack << (ancestors.include?("Minitest::Spec") ? ClassGroup.new(name) : nil)
        end
      end

      #: (Prism::ClassNode) -> void
      def on_class_node_leave(node) # rubocop:disable RubyLsp/UseRegisterWithHandlerMethod
        super
        @spec_group_id_stack.pop
      end

      #: (Prism::CallNode) -> void
      def on_call_node_enter(node)
        return unless in_spec_context?

        case node.name
        when :describe
          handle_describe(node)
        when :it, :specify
          handle_example(node)
        end
      end

      #: (Prism::CallNode) -> void
      def on_call_node_leave(node)
        return unless node.name == :describe && !node.receiver

        @spec_group_id_stack.pop
      end

      private

      #: (Prism::CallNode) -> void
      def handle_describe(node)
        # Describes will include the nesting of all classes and all outer describes as part of its ID, unlike classes
        # that ignore describes
        return if node.block.nil?

        description = extract_description(node)
        return unless description

        parent = latest_group
        id = case parent
        when Requests::Support::TestItem
          "#{parent.id}::#{description}"
        else
          description
        end

        test_item = Requests::Support::TestItem.new(
          id,
          description,
          @uri,
          range_from_node(node),
          framework: :minitest,
        )

        parent.add(test_item)
        @response_builder.add_code_lens(test_item)
        @spec_group_id_stack << DescribeGroup.new(id)
      end

      #: (Prism::CallNode) -> void
      def handle_example(node)
        # Minitest formats the descriptions into test method names by using the count of examples with the description
        # We are not guaranteed to discover examples in the exact order using static analysis, so we use the line number
        # instead. Note that anonymous examples mixed with meta-programming will not be handled correctly
        description = extract_description(node) || "anonymous"
        line = node.location.start_line - 1
        parent = latest_group
        return unless parent.is_a?(Requests::Support::TestItem)

        id = "#{parent.id}##{format("test_%04d_%s", line, description)}"

        test_item = Requests::Support::TestItem.new(
          id,
          description,
          @uri,
          range_from_node(node),
          framework: :minitest,
        )

        parent.add(test_item)
        @response_builder.add_code_lens(test_item)
      end

      #: (Prism::CallNode) -> String?
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

      #: -> (Requests::Support::TestItem | ResponseBuilders::TestCollection)
      def latest_group
        return @response_builder if @spec_group_id_stack.compact.empty?

        first_class_index = @spec_group_id_stack.rindex { |i| i.is_a?(ClassGroup) } || 0
        first_class = @spec_group_id_stack[0] #: as !nil
        item = @response_builder[first_class.id] #: as !nil

        # Descend into child items from the beginning all the way to the latest class group, ignoring describes
        @spec_group_id_stack[1..first_class_index] #: as !nil
          .each do |group|
          next unless group.is_a?(ClassGroup)

          item = item[group.id] #: as !nil
        end

        # From the class forward, we must take describes into account
        @spec_group_id_stack[first_class_index + 1..] #: as !nil
          .each do |group|
          next unless group

          item = item[group.id] #: as !nil
        end

        item
      end

      #: -> bool
      def in_spec_context?
        @nesting.empty? || @spec_group_id_stack.any? { |id| id }
      end
    end
  end
end
