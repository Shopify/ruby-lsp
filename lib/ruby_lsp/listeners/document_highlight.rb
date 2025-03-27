# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class DocumentHighlight
      include Requests::Support::Common

      GLOBAL_VARIABLE_NODES = [
        Prism::GlobalVariableAndWriteNode,
        Prism::GlobalVariableOperatorWriteNode,
        Prism::GlobalVariableOrWriteNode,
        Prism::GlobalVariableReadNode,
        Prism::GlobalVariableTargetNode,
        Prism::GlobalVariableWriteNode,
      ] #: Array[singleton(Prism::Node)]

      INSTANCE_VARIABLE_NODES = [
        Prism::InstanceVariableAndWriteNode,
        Prism::InstanceVariableOperatorWriteNode,
        Prism::InstanceVariableOrWriteNode,
        Prism::InstanceVariableReadNode,
        Prism::InstanceVariableTargetNode,
        Prism::InstanceVariableWriteNode,
      ] #: Array[singleton(Prism::Node)]

      CONSTANT_NODES = [
        Prism::ConstantAndWriteNode,
        Prism::ConstantOperatorWriteNode,
        Prism::ConstantOrWriteNode,
        Prism::ConstantReadNode,
        Prism::ConstantTargetNode,
        Prism::ConstantWriteNode,
      ] #: Array[singleton(Prism::Node)]

      CONSTANT_PATH_NODES = [
        Prism::ConstantPathAndWriteNode,
        Prism::ConstantPathNode,
        Prism::ConstantPathOperatorWriteNode,
        Prism::ConstantPathOrWriteNode,
        Prism::ConstantPathTargetNode,
        Prism::ConstantPathWriteNode,
      ] #: Array[singleton(Prism::Node)]

      CLASS_VARIABLE_NODES = [
        Prism::ClassVariableAndWriteNode,
        Prism::ClassVariableOperatorWriteNode,
        Prism::ClassVariableOrWriteNode,
        Prism::ClassVariableReadNode,
        Prism::ClassVariableTargetNode,
        Prism::ClassVariableWriteNode,
      ] #: Array[singleton(Prism::Node)]

      LOCAL_NODES = [
        Prism::LocalVariableAndWriteNode,
        Prism::LocalVariableOperatorWriteNode,
        Prism::LocalVariableOrWriteNode,
        Prism::LocalVariableReadNode,
        Prism::LocalVariableTargetNode,
        Prism::LocalVariableWriteNode,
        Prism::BlockParameterNode,
        Prism::RequiredParameterNode,
        Prism::RequiredKeywordParameterNode,
        Prism::OptionalKeywordParameterNode,
        Prism::RestParameterNode,
        Prism::OptionalParameterNode,
        Prism::KeywordRestParameterNode,
      ] #: Array[singleton(Prism::Node)]

      #: (ResponseBuilders::CollectionResponseBuilder[Interface::DocumentHighlight] response_builder, Prism::Node? target, Prism::Node? parent, Prism::Dispatcher dispatcher, Hash[Symbol, untyped] position) -> void
      def initialize(response_builder, target, parent, dispatcher, position)
        @response_builder = response_builder

        return unless target && parent

        highlight_target, highlight_target_value =
          case target
          when Prism::GlobalVariableReadNode, Prism::GlobalVariableAndWriteNode, Prism::GlobalVariableOperatorWriteNode,
            Prism::GlobalVariableOrWriteNode, Prism::GlobalVariableTargetNode, Prism::GlobalVariableWriteNode,
            Prism::InstanceVariableAndWriteNode, Prism::InstanceVariableOperatorWriteNode,
            Prism::InstanceVariableOrWriteNode, Prism::InstanceVariableReadNode, Prism::InstanceVariableTargetNode,
            Prism::InstanceVariableWriteNode, Prism::ConstantAndWriteNode, Prism::ConstantOperatorWriteNode,
            Prism::ConstantOrWriteNode, Prism::ConstantPathAndWriteNode, Prism::ConstantPathNode,
            Prism::ConstantPathOperatorWriteNode, Prism::ConstantPathOrWriteNode, Prism::ConstantPathTargetNode,
            Prism::ConstantPathWriteNode, Prism::ConstantReadNode, Prism::ConstantTargetNode, Prism::ConstantWriteNode,
            Prism::ClassVariableAndWriteNode, Prism::ClassVariableOperatorWriteNode, Prism::ClassVariableOrWriteNode,
            Prism::ClassVariableReadNode, Prism::ClassVariableTargetNode, Prism::ClassVariableWriteNode,
            Prism::LocalVariableAndWriteNode, Prism::LocalVariableOperatorWriteNode, Prism::LocalVariableOrWriteNode,
            Prism::LocalVariableReadNode, Prism::LocalVariableTargetNode, Prism::LocalVariableWriteNode,
            Prism::CallNode, Prism::BlockParameterNode, Prism::RequiredKeywordParameterNode,
            Prism::RequiredKeywordParameterNode, Prism::KeywordRestParameterNode, Prism::OptionalParameterNode,
            Prism::RequiredParameterNode, Prism::RestParameterNode
            [target, node_value(target)]
          when Prism::ModuleNode, Prism::ClassNode, Prism::SingletonClassNode, Prism::DefNode, Prism::CaseNode,
            Prism::WhileNode, Prism::UntilNode, Prism::ForNode, Prism::IfNode, Prism::UnlessNode
            [target, nil]
          end

        @target = highlight_target #: Prism::Node?
        @target_value = highlight_target_value #: String?
        @target_position = position

        if @target
          dispatcher.register(
            self,
            :on_call_node_enter,
            :on_def_node_enter,
            :on_global_variable_target_node_enter,
            :on_instance_variable_target_node_enter,
            :on_constant_path_target_node_enter,
            :on_constant_target_node_enter,
            :on_class_variable_target_node_enter,
            :on_local_variable_target_node_enter,
            :on_block_parameter_node_enter,
            :on_required_parameter_node_enter,
            :on_class_node_enter,
            :on_module_node_enter,
            :on_local_variable_read_node_enter,
            :on_constant_path_node_enter,
            :on_constant_read_node_enter,
            :on_instance_variable_read_node_enter,
            :on_class_variable_read_node_enter,
            :on_global_variable_read_node_enter,
            :on_constant_path_write_node_enter,
            :on_constant_path_or_write_node_enter,
            :on_constant_path_and_write_node_enter,
            :on_constant_path_operator_write_node_enter,
            :on_local_variable_write_node_enter,
            :on_required_keyword_parameter_node_enter,
            :on_optional_keyword_parameter_node_enter,
            :on_rest_parameter_node_enter,
            :on_optional_parameter_node_enter,
            :on_keyword_rest_parameter_node_enter,
            :on_local_variable_and_write_node_enter,
            :on_local_variable_operator_write_node_enter,
            :on_local_variable_or_write_node_enter,
            :on_class_variable_write_node_enter,
            :on_class_variable_or_write_node_enter,
            :on_class_variable_operator_write_node_enter,
            :on_class_variable_and_write_node_enter,
            :on_constant_write_node_enter,
            :on_constant_or_write_node_enter,
            :on_constant_operator_write_node_enter,
            :on_instance_variable_write_node_enter,
            :on_constant_and_write_node_enter,
            :on_instance_variable_or_write_node_enter,
            :on_instance_variable_and_write_node_enter,
            :on_instance_variable_operator_write_node_enter,
            :on_global_variable_write_node_enter,
            :on_global_variable_or_write_node_enter,
            :on_global_variable_and_write_node_enter,
            :on_global_variable_operator_write_node_enter,
            :on_singleton_class_node_enter,
            :on_case_node_enter,
            :on_while_node_enter,
            :on_until_node_enter,
            :on_for_node_enter,
            :on_if_node_enter,
            :on_unless_node_enter,
          )
        end
      end

      #: (Prism::CallNode node) -> void
      def on_call_node_enter(node)
        return unless matches?(node, [Prism::CallNode, Prism::DefNode])

        loc = node.message_loc
        # if we have `foo.` it's a call node but there is no message yet.
        return unless loc

        add_highlight(Constant::DocumentHighlightKind::READ, loc)
      end

      #: (Prism::DefNode node) -> void
      def on_def_node_enter(node)
        add_matching_end_highlights(node.def_keyword_loc, node.end_keyword_loc) if @target.is_a?(Prism::DefNode)

        return unless matches?(node, [Prism::CallNode, Prism::DefNode])

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::GlobalVariableTargetNode node) -> void
      def on_global_variable_target_node_enter(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      #: (Prism::InstanceVariableTargetNode node) -> void
      def on_instance_variable_target_node_enter(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      #: (Prism::ConstantPathTargetNode node) -> void
      def on_constant_path_target_node_enter(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      #: (Prism::ConstantTargetNode node) -> void
      def on_constant_target_node_enter(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      #: (Prism::ClassVariableTargetNode node) -> void
      def on_class_variable_target_node_enter(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      #: (Prism::LocalVariableTargetNode node) -> void
      def on_local_variable_target_node_enter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      #: (Prism::BlockParameterNode node) -> void
      def on_block_parameter_node_enter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      #: (Prism::RequiredParameterNode node) -> void
      def on_required_parameter_node_enter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      #: (Prism::ClassNode node) -> void
      def on_class_node_enter(node)
        add_matching_end_highlights(node.class_keyword_loc, node.end_keyword_loc) if @target.is_a?(Prism::ClassNode)

        return unless matches?(node, CONSTANT_NODES + CONSTANT_PATH_NODES + [Prism::ClassNode])

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.constant_path.location)
      end

      #: (Prism::ModuleNode node) -> void
      def on_module_node_enter(node)
        add_matching_end_highlights(node.module_keyword_loc, node.end_keyword_loc) if @target.is_a?(Prism::ModuleNode)

        return unless matches?(node, CONSTANT_NODES + CONSTANT_PATH_NODES + [Prism::ModuleNode])

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.constant_path.location)
      end

      #: (Prism::LocalVariableReadNode node) -> void
      def on_local_variable_read_node_enter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      #: (Prism::ConstantPathNode node) -> void
      def on_constant_path_node_enter(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.name_loc)
      end

      #: (Prism::ConstantReadNode node) -> void
      def on_constant_read_node_enter(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      #: (Prism::InstanceVariableReadNode node) -> void
      def on_instance_variable_read_node_enter(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      #: (Prism::ClassVariableReadNode node) -> void
      def on_class_variable_read_node_enter(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      #: (Prism::GlobalVariableReadNode node) -> void
      def on_global_variable_read_node_enter(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      #: (Prism::ConstantPathWriteNode node) -> void
      def on_constant_path_write_node_enter(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.target.location)
      end

      #: (Prism::ConstantPathOrWriteNode node) -> void
      def on_constant_path_or_write_node_enter(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.target.location)
      end

      #: (Prism::ConstantPathAndWriteNode node) -> void
      def on_constant_path_and_write_node_enter(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.target.location)
      end

      #: (Prism::ConstantPathOperatorWriteNode node) -> void
      def on_constant_path_operator_write_node_enter(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.target.location)
      end

      #: (Prism::LocalVariableWriteNode node) -> void
      def on_local_variable_write_node_enter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::RequiredKeywordParameterNode node) -> void
      def on_required_keyword_parameter_node_enter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::OptionalKeywordParameterNode node) -> void
      def on_optional_keyword_parameter_node_enter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::RestParameterNode node) -> void
      def on_rest_parameter_node_enter(node)
        return unless matches?(node, LOCAL_NODES)

        name_loc = node.name_loc
        add_highlight(Constant::DocumentHighlightKind::WRITE, name_loc) if name_loc
      end

      #: (Prism::OptionalParameterNode node) -> void
      def on_optional_parameter_node_enter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::KeywordRestParameterNode node) -> void
      def on_keyword_rest_parameter_node_enter(node)
        return unless matches?(node, LOCAL_NODES)

        name_loc = node.name_loc
        add_highlight(Constant::DocumentHighlightKind::WRITE, name_loc) if name_loc
      end

      #: (Prism::LocalVariableAndWriteNode node) -> void
      def on_local_variable_and_write_node_enter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::LocalVariableOperatorWriteNode node) -> void
      def on_local_variable_operator_write_node_enter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::LocalVariableOrWriteNode node) -> void
      def on_local_variable_or_write_node_enter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::ClassVariableWriteNode node) -> void
      def on_class_variable_write_node_enter(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::ClassVariableOrWriteNode node) -> void
      def on_class_variable_or_write_node_enter(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::ClassVariableOperatorWriteNode node) -> void
      def on_class_variable_operator_write_node_enter(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::ClassVariableAndWriteNode node) -> void
      def on_class_variable_and_write_node_enter(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::ConstantWriteNode node) -> void
      def on_constant_write_node_enter(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::ConstantOrWriteNode node) -> void
      def on_constant_or_write_node_enter(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::ConstantOperatorWriteNode node) -> void
      def on_constant_operator_write_node_enter(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::InstanceVariableWriteNode node) -> void
      def on_instance_variable_write_node_enter(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::InstanceVariableOrWriteNode node) -> void
      def on_instance_variable_or_write_node_enter(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::InstanceVariableAndWriteNode node) -> void
      def on_instance_variable_and_write_node_enter(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::InstanceVariableOperatorWriteNode node) -> void
      def on_instance_variable_operator_write_node_enter(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::ConstantAndWriteNode node) -> void
      def on_constant_and_write_node_enter(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::GlobalVariableWriteNode node) -> void
      def on_global_variable_write_node_enter(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::GlobalVariableOrWriteNode node) -> void
      def on_global_variable_or_write_node_enter(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::GlobalVariableAndWriteNode node) -> void
      def on_global_variable_and_write_node_enter(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::GlobalVariableOperatorWriteNode node) -> void
      def on_global_variable_operator_write_node_enter(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      #: (Prism::SingletonClassNode node) -> void
      def on_singleton_class_node_enter(node)
        return unless @target.is_a?(Prism::SingletonClassNode)

        add_matching_end_highlights(node.class_keyword_loc, node.end_keyword_loc)
      end

      #: (Prism::CaseNode node) -> void
      def on_case_node_enter(node)
        return unless @target.is_a?(Prism::CaseNode)

        add_matching_end_highlights(node.case_keyword_loc, node.end_keyword_loc)
      end

      #: (Prism::WhileNode node) -> void
      def on_while_node_enter(node)
        return unless @target.is_a?(Prism::WhileNode)

        add_matching_end_highlights(node.keyword_loc, node.closing_loc)
      end

      #: (Prism::UntilNode node) -> void
      def on_until_node_enter(node)
        return unless @target.is_a?(Prism::UntilNode)

        add_matching_end_highlights(node.keyword_loc, node.closing_loc)
      end

      #: (Prism::ForNode node) -> void
      def on_for_node_enter(node)
        return unless @target.is_a?(Prism::ForNode)

        add_matching_end_highlights(node.for_keyword_loc, node.end_keyword_loc)
      end

      #: (Prism::IfNode node) -> void
      def on_if_node_enter(node)
        return unless @target.is_a?(Prism::IfNode)

        add_matching_end_highlights(node.if_keyword_loc, node.end_keyword_loc)
      end

      #: (Prism::UnlessNode node) -> void
      def on_unless_node_enter(node)
        return unless @target.is_a?(Prism::UnlessNode)

        add_matching_end_highlights(node.keyword_loc, node.end_keyword_loc)
      end

      private

      #: (Prism::Node node, Array[singleton(Prism::Node)] classes) -> bool?
      def matches?(node, classes)
        classes.any? { |klass| @target.is_a?(klass) } && @target_value == node_value(node)
      end

      #: (Integer kind, Prism::Location location) -> void
      def add_highlight(kind, location)
        @response_builder << Interface::DocumentHighlight.new(range: range_from_location(location), kind: kind)
      end

      #: (Prism::Node? node) -> String?
      def node_value(node)
        case node
        when Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::BlockArgumentNode, Prism::ConstantTargetNode,
          Prism::ConstantPathWriteNode, Prism::ConstantPathTargetNode, Prism::ConstantPathOrWriteNode,
          Prism::ConstantPathOperatorWriteNode, Prism::ConstantPathAndWriteNode
          node.slice
        when Prism::GlobalVariableReadNode, Prism::GlobalVariableAndWriteNode, Prism::GlobalVariableOperatorWriteNode,
          Prism::GlobalVariableOrWriteNode, Prism::GlobalVariableTargetNode, Prism::GlobalVariableWriteNode,
          Prism::InstanceVariableAndWriteNode, Prism::InstanceVariableOperatorWriteNode,
          Prism::InstanceVariableOrWriteNode, Prism::InstanceVariableReadNode, Prism::InstanceVariableTargetNode,
          Prism::InstanceVariableWriteNode, Prism::ConstantAndWriteNode, Prism::ConstantOperatorWriteNode,
          Prism::ConstantOrWriteNode, Prism::ConstantWriteNode, Prism::ClassVariableAndWriteNode,
          Prism::ClassVariableOperatorWriteNode, Prism::ClassVariableOrWriteNode, Prism::ClassVariableReadNode,
          Prism::ClassVariableTargetNode, Prism::ClassVariableWriteNode, Prism::LocalVariableAndWriteNode,
          Prism::LocalVariableOperatorWriteNode, Prism::LocalVariableOrWriteNode, Prism::LocalVariableReadNode,
          Prism::LocalVariableTargetNode, Prism::LocalVariableWriteNode, Prism::DefNode, Prism::BlockParameterNode,
          Prism::RequiredKeywordParameterNode, Prism::OptionalKeywordParameterNode, Prism::KeywordRestParameterNode,
          Prism::OptionalParameterNode, Prism::RequiredParameterNode, Prism::RestParameterNode

          node.name.to_s
        when Prism::CallNode
          node.message
        when Prism::ClassNode, Prism::ModuleNode
          node.constant_path.slice
        end
      end

      #: (Prism::Location? keyword_loc, Prism::Location? end_loc) -> void
      def add_matching_end_highlights(keyword_loc, end_loc)
        return unless keyword_loc && end_loc
        return unless end_loc.length.positive?
        return unless covers_target_position?(keyword_loc) || covers_target_position?(end_loc)

        add_highlight(Constant::DocumentHighlightKind::TEXT, keyword_loc)
        add_highlight(Constant::DocumentHighlightKind::TEXT, end_loc)
      end

      #: (Prism::Location location) -> bool
      def covers_target_position?(location)
        start_line = location.start_line - 1
        end_line = location.end_line - 1
        start_covered = start_line < @target_position[:line] ||
          (start_line == @target_position[:line] && location.start_column <= @target_position[:character])
        end_covered = end_line > @target_position[:line] ||
          (end_line == @target_position[:line] && location.end_column >= @target_position[:character])
        start_covered && end_covered
      end
    end
  end
end
