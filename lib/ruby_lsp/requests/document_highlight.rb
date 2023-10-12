# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Document highlight demo](../../document_highlight.gif)
    #
    # The [document highlight](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentHighlight)
    # informs the editor all relevant elements of the currently pointed item for highlighting. For example, when
    # the cursor is on the `F` of the constant `FOO`, the editor should identify other occurrences of `FOO`
    # and highlight them.
    #
    # For writable elements like constants or variables, their read/write occurrences should be highlighted differently.
    # This is achieved by sending different "kind" attributes to the editor (2 for read and 3 for write).
    #
    # # Example
    #
    # ```ruby
    # FOO = 1 # should be highlighted as "write"
    #
    # def foo
    #   FOO # should be highlighted as "read"
    # end
    # ```
    class DocumentHighlight < Listener
      extend T::Sig

      ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

      GLOBAL_VARIABLE_NODES = T.let(
        [
          Prism::GlobalVariableAndWriteNode,
          Prism::GlobalVariableOperatorWriteNode,
          Prism::GlobalVariableOrWriteNode,
          Prism::GlobalVariableReadNode,
          Prism::GlobalVariableTargetNode,
          Prism::GlobalVariableWriteNode,
        ],
        T::Array[T.class_of(Prism::Node)],
      )

      INSTANCE_VARIABLE_NODES = T.let(
        [
          Prism::InstanceVariableAndWriteNode,
          Prism::InstanceVariableOperatorWriteNode,
          Prism::InstanceVariableOrWriteNode,
          Prism::InstanceVariableReadNode,
          Prism::InstanceVariableTargetNode,
          Prism::InstanceVariableWriteNode,
        ],
        T::Array[T.class_of(Prism::Node)],
      )

      CONSTANT_NODES = T.let(
        [
          Prism::ConstantAndWriteNode,
          Prism::ConstantOperatorWriteNode,
          Prism::ConstantOrWriteNode,
          Prism::ConstantReadNode,
          Prism::ConstantTargetNode,
          Prism::ConstantWriteNode,
        ],
        T::Array[T.class_of(Prism::Node)],
      )

      CONSTANT_PATH_NODES = T.let(
        [
          Prism::ConstantPathAndWriteNode,
          Prism::ConstantPathNode,
          Prism::ConstantPathOperatorWriteNode,
          Prism::ConstantPathOrWriteNode,
          Prism::ConstantPathTargetNode,
          Prism::ConstantPathWriteNode,
        ],
        T::Array[T.class_of(Prism::Node)],
      )

      CLASS_VARIABLE_NODES = T.let(
        [
          Prism::ClassVariableAndWriteNode,
          Prism::ClassVariableOperatorWriteNode,
          Prism::ClassVariableOrWriteNode,
          Prism::ClassVariableReadNode,
          Prism::ClassVariableTargetNode,
          Prism::ClassVariableWriteNode,
        ],
        T::Array[T.class_of(Prism::Node)],
      )

      LOCAL_NODES = T.let(
        [
          Prism::LocalVariableAndWriteNode,
          Prism::LocalVariableOperatorWriteNode,
          Prism::LocalVariableOrWriteNode,
          Prism::LocalVariableReadNode,
          Prism::LocalVariableTargetNode,
          Prism::LocalVariableWriteNode,
          Prism::BlockParameterNode,
          Prism::RequiredParameterNode,
          Prism::KeywordParameterNode,
          Prism::RestParameterNode,
          Prism::OptionalParameterNode,
          Prism::KeywordRestParameterNode,
        ],
        T::Array[T.class_of(Prism::Node)],
      )

      sig { override.returns(ResponseType) }
      attr_reader :_response

      sig do
        params(
          target: T.nilable(Prism::Node),
          parent: T.nilable(Prism::Node),
          emitter: EventEmitter,
          message_queue: Thread::Queue,
        ).void
      end
      def initialize(target, parent, emitter, message_queue)
        super(emitter, message_queue)

        @_response = T.let([], T::Array[Interface::DocumentHighlight])

        return unless target && parent

        highlight_target =
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
            Prism::CallNode, Prism::BlockParameterNode, Prism::KeywordParameterNode, Prism::KeywordRestParameterNode,
            Prism::OptionalParameterNode, Prism::RequiredParameterNode, Prism::RestParameterNode
            target
          end

        @target = T.let(highlight_target, T.nilable(Prism::Node))
        @target_value = T.let(node_value(highlight_target), T.nilable(String))

        if @target && @target_value
          emitter.register(
            self,
            :on_call,
            :on_def,
            :on_global_variable_target,
            :on_instance_variable_target,
            :on_constant_path_target,
            :on_constant_target,
            :on_class_variable_target,
            :on_local_variable_target,
            :on_block_parameter,
            :on_required_parameter,
            :on_class,
            :on_module,
            :on_local_variable_read,
            :on_constant_path,
            :on_constant_read,
            :on_instance_variable_read,
            :on_class_variable_read,
            :on_global_variable_read,
            :on_constant_path_write,
            :on_constant_path_or_write,
            :on_constant_path_and_write,
            :on_constant_path_operator_write,
            :on_local_variable_write,
            :on_keyword_parameter,
            :on_rest_parameter,
            :on_optional_parameter,
            :on_keyword_rest_parameter,
            :on_local_variable_and_write,
            :on_local_variable_operator_write,
            :on_local_variable_or_write,
            :on_class_variable_write,
            :on_class_variable_or_write,
            :on_class_variable_operator_write,
            :on_class_variable_and_write,
            :on_constant_write,
            :on_constant_or_write,
            :on_constant_operator_write,
            :on_instance_variable_write,
            :on_constant_and_write,
            :on_instance_variable_or_write,
            :on_instance_variable_and_write,
            :on_instance_variable_operator_write,
            :on_global_variable_write,
            :on_global_variable_or_write,
            :on_global_variable_and_write,
            :on_global_variable_operator_write,
          )
        end
      end

      sig { params(node: Prism::CallNode).void }
      def on_call(node)
        return unless matches?(node, [Prism::CallNode, Prism::DefNode])

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      sig { params(node: Prism::DefNode).void }
      def on_def(node)
        return unless matches?(node, [Prism::CallNode, Prism::DefNode])

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::GlobalVariableTargetNode).void }
      def on_global_variable_target(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: Prism::InstanceVariableTargetNode).void }
      def on_instance_variable_target(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: Prism::ConstantPathTargetNode).void }
      def on_constant_path_target(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: Prism::ConstantTargetNode).void }
      def on_constant_target(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: Prism::ClassVariableTargetNode).void }
      def on_class_variable_target(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: Prism::LocalVariableTargetNode).void }
      def on_local_variable_target(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: Prism::BlockParameterNode).void }
      def on_block_parameter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: Prism::RequiredParameterNode).void }
      def on_required_parameter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class(node)
        return unless matches?(node, CONSTANT_NODES + CONSTANT_PATH_NODES + [Prism::ClassNode])

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.constant_path.location)
      end

      sig { params(node: Prism::ModuleNode).void }
      def on_module(node)
        return unless matches?(node, CONSTANT_NODES + CONSTANT_PATH_NODES + [Prism::ModuleNode])

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.constant_path.location)
      end

      sig { params(node: Prism::LocalVariableReadNode).void }
      def on_local_variable_read(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      sig { params(node: Prism::ConstantPathNode).void }
      def on_constant_path(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      sig { params(node: Prism::ConstantReadNode).void }
      def on_constant_read(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      sig { params(node: Prism::InstanceVariableReadNode).void }
      def on_instance_variable_read(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      sig { params(node: Prism::ClassVariableReadNode).void }
      def on_class_variable_read(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      sig { params(node: Prism::GlobalVariableReadNode).void }
      def on_global_variable_read(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      sig { params(node: Prism::ConstantPathWriteNode).void }
      def on_constant_path_write(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.target.location)
      end

      sig { params(node: Prism::ConstantPathOrWriteNode).void }
      def on_constant_path_or_write(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.target.location)
      end

      sig { params(node: Prism::ConstantPathAndWriteNode).void }
      def on_constant_path_and_write(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.target.location)
      end

      sig { params(node: Prism::ConstantPathOperatorWriteNode).void }
      def on_constant_path_operator_write(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.target.location)
      end

      sig { params(node: Prism::LocalVariableWriteNode).void }
      def on_local_variable_write(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::KeywordParameterNode).void }
      def on_keyword_parameter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::RestParameterNode).void }
      def on_rest_parameter(node)
        return unless matches?(node, LOCAL_NODES)

        name_loc = node.name_loc
        add_highlight(Constant::DocumentHighlightKind::WRITE, name_loc) if name_loc
      end

      sig { params(node: Prism::OptionalParameterNode).void }
      def on_optional_parameter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::KeywordRestParameterNode).void }
      def on_keyword_rest_parameter(node)
        return unless matches?(node, LOCAL_NODES)

        name_loc = node.name_loc
        add_highlight(Constant::DocumentHighlightKind::WRITE, name_loc) if name_loc
      end

      sig { params(node: Prism::LocalVariableAndWriteNode).void }
      def on_local_variable_and_write(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::LocalVariableOperatorWriteNode).void }
      def on_local_variable_operator_write(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::LocalVariableOrWriteNode).void }
      def on_local_variable_or_write(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::ClassVariableWriteNode).void }
      def on_class_variable_write(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::ClassVariableOrWriteNode).void }
      def on_class_variable_or_write(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::ClassVariableOperatorWriteNode).void }
      def on_class_variable_operator_write(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::ClassVariableAndWriteNode).void }
      def on_class_variable_and_write(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::ConstantWriteNode).void }
      def on_constant_write(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::ConstantOrWriteNode).void }
      def on_constant_or_write(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::ConstantOperatorWriteNode).void }
      def on_constant_operator_write(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::InstanceVariableWriteNode).void }
      def on_instance_variable_write(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::InstanceVariableOrWriteNode).void }
      def on_instance_variable_or_write(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::InstanceVariableAndWriteNode).void }
      def on_instance_variable_and_write(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::InstanceVariableOperatorWriteNode).void }
      def on_instance_variable_operator_write(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::ConstantAndWriteNode).void }
      def on_constant_and_write(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::GlobalVariableWriteNode).void }
      def on_global_variable_write(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::GlobalVariableOrWriteNode).void }
      def on_global_variable_or_write(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::GlobalVariableAndWriteNode).void }
      def on_global_variable_and_write(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: Prism::GlobalVariableOperatorWriteNode).void }
      def on_global_variable_operator_write(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      private

      sig { params(node: Prism::Node, classes: T::Array[T.class_of(Prism::Node)]).returns(T.nilable(T::Boolean)) }
      def matches?(node, classes)
        classes.any? { |klass| @target.is_a?(klass) } && @target_value == node_value(node)
      end

      sig { params(kind: Integer, location: Prism::Location).void }
      def add_highlight(kind, location)
        @_response << Interface::DocumentHighlight.new(range: range_from_location(location), kind: kind)
      end

      sig { params(node: T.nilable(Prism::Node)).returns(T.nilable(String)) }
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
          Prism::KeywordParameterNode, Prism::KeywordRestParameterNode, Prism::OptionalParameterNode,
          Prism::RequiredParameterNode, Prism::RestParameterNode

          node.name.to_s
        when Prism::CallNode
          node.message
        when Prism::ClassNode, Prism::ModuleNode
          node.constant_path.slice
        end
      end
    end
  end
end
