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
          YARP::GlobalVariableAndWriteNode,
          YARP::GlobalVariableOperatorWriteNode,
          YARP::GlobalVariableOrWriteNode,
          YARP::GlobalVariableReadNode,
          YARP::GlobalVariableTargetNode,
          YARP::GlobalVariableWriteNode,
        ],
        T::Array[T.class_of(YARP::Node)],
      )

      INSTANCE_VARIABLE_NODES = T.let(
        [
          YARP::InstanceVariableAndWriteNode,
          YARP::InstanceVariableOperatorWriteNode,
          YARP::InstanceVariableOrWriteNode,
          YARP::InstanceVariableReadNode,
          YARP::InstanceVariableTargetNode,
          YARP::InstanceVariableWriteNode,
        ],
        T::Array[T.class_of(YARP::Node)],
      )

      CONSTANT_NODES = T.let(
        [
          YARP::ConstantAndWriteNode,
          YARP::ConstantOperatorWriteNode,
          YARP::ConstantOrWriteNode,
          YARP::ConstantReadNode,
          YARP::ConstantTargetNode,
          YARP::ConstantWriteNode,
        ],
        T::Array[T.class_of(YARP::Node)],
      )

      CONSTANT_PATH_NODES = T.let(
        [
          YARP::ConstantPathAndWriteNode,
          YARP::ConstantPathNode,
          YARP::ConstantPathOperatorWriteNode,
          YARP::ConstantPathOrWriteNode,
          YARP::ConstantPathTargetNode,
          YARP::ConstantPathWriteNode,
        ],
        T::Array[T.class_of(YARP::Node)],
      )

      CLASS_VARIABLE_NODES = T.let(
        [
          YARP::ClassVariableAndWriteNode,
          YARP::ClassVariableOperatorWriteNode,
          YARP::ClassVariableOrWriteNode,
          YARP::ClassVariableReadNode,
          YARP::ClassVariableTargetNode,
          YARP::ClassVariableWriteNode,
        ],
        T::Array[T.class_of(YARP::Node)],
      )

      LOCAL_NODES = T.let(
        [
          YARP::LocalVariableAndWriteNode,
          YARP::LocalVariableOperatorWriteNode,
          YARP::LocalVariableOrWriteNode,
          YARP::LocalVariableReadNode,
          YARP::LocalVariableTargetNode,
          YARP::LocalVariableWriteNode,
          YARP::BlockParameterNode,
          YARP::RequiredParameterNode,
          YARP::KeywordParameterNode,
          YARP::RestParameterNode,
          YARP::OptionalParameterNode,
          YARP::KeywordRestParameterNode,
        ],
        T::Array[T.class_of(YARP::Node)],
      )

      sig { override.returns(ResponseType) }
      attr_reader :_response

      sig do
        params(
          target: T.nilable(YARP::Node),
          parent: T.nilable(YARP::Node),
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
          when YARP::GlobalVariableReadNode, YARP::GlobalVariableAndWriteNode, YARP::GlobalVariableOperatorWriteNode,
            YARP::GlobalVariableOrWriteNode, YARP::GlobalVariableTargetNode, YARP::GlobalVariableWriteNode,
            YARP::InstanceVariableAndWriteNode, YARP::InstanceVariableOperatorWriteNode,
            YARP::InstanceVariableOrWriteNode, YARP::InstanceVariableReadNode, YARP::InstanceVariableTargetNode,
            YARP::InstanceVariableWriteNode, YARP::ConstantAndWriteNode, YARP::ConstantOperatorWriteNode,
            YARP::ConstantOrWriteNode, YARP::ConstantPathAndWriteNode, YARP::ConstantPathNode,
            YARP::ConstantPathOperatorWriteNode, YARP::ConstantPathOrWriteNode, YARP::ConstantPathTargetNode,
            YARP::ConstantPathWriteNode, YARP::ConstantReadNode, YARP::ConstantTargetNode, YARP::ConstantWriteNode,
            YARP::ClassVariableAndWriteNode, YARP::ClassVariableOperatorWriteNode, YARP::ClassVariableOrWriteNode,
            YARP::ClassVariableReadNode, YARP::ClassVariableTargetNode, YARP::ClassVariableWriteNode,
            YARP::LocalVariableAndWriteNode, YARP::LocalVariableOperatorWriteNode, YARP::LocalVariableOrWriteNode,
            YARP::LocalVariableReadNode, YARP::LocalVariableTargetNode, YARP::LocalVariableWriteNode, YARP::CallNode,
            YARP::BlockParameterNode, YARP::KeywordParameterNode, YARP::KeywordRestParameterNode,
            YARP::OptionalParameterNode, YARP::RequiredParameterNode, YARP::RestParameterNode
            target
          end

        @target = T.let(highlight_target, T.nilable(YARP::Node))
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

      sig { params(node: YARP::CallNode).void }
      def on_call(node)
        return unless matches?(node, [YARP::CallNode, YARP::DefNode])

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      sig { params(node: YARP::DefNode).void }
      def on_def(node)
        return unless matches?(node, [YARP::CallNode, YARP::DefNode])

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::GlobalVariableTargetNode).void }
      def on_global_variable_target(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: YARP::InstanceVariableTargetNode).void }
      def on_instance_variable_target(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: YARP::ConstantPathTargetNode).void }
      def on_constant_path_target(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: YARP::ConstantTargetNode).void }
      def on_constant_target(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: YARP::ClassVariableTargetNode).void }
      def on_class_variable_target(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: YARP::LocalVariableTargetNode).void }
      def on_local_variable_target(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: YARP::BlockParameterNode).void }
      def on_block_parameter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: YARP::RequiredParameterNode).void }
      def on_required_parameter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.location)
      end

      sig { params(node: YARP::ClassNode).void }
      def on_class(node)
        return unless matches?(node, CONSTANT_NODES + CONSTANT_PATH_NODES + [YARP::ClassNode])

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.constant_path.location)
      end

      sig { params(node: YARP::ModuleNode).void }
      def on_module(node)
        return unless matches?(node, CONSTANT_NODES + CONSTANT_PATH_NODES + [YARP::ModuleNode])

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.constant_path.location)
      end

      sig { params(node: YARP::LocalVariableReadNode).void }
      def on_local_variable_read(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      sig { params(node: YARP::ConstantPathNode).void }
      def on_constant_path(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      sig { params(node: YARP::ConstantReadNode).void }
      def on_constant_read(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      sig { params(node: YARP::InstanceVariableReadNode).void }
      def on_instance_variable_read(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      sig { params(node: YARP::ClassVariableReadNode).void }
      def on_class_variable_read(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      sig { params(node: YARP::GlobalVariableReadNode).void }
      def on_global_variable_read(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::READ, node.location)
      end

      sig { params(node: YARP::ConstantPathWriteNode).void }
      def on_constant_path_write(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.target.location)
      end

      sig { params(node: YARP::ConstantPathOrWriteNode).void }
      def on_constant_path_or_write(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.target.location)
      end

      sig { params(node: YARP::ConstantPathAndWriteNode).void }
      def on_constant_path_and_write(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.target.location)
      end

      sig { params(node: YARP::ConstantPathOperatorWriteNode).void }
      def on_constant_path_operator_write(node)
        return unless matches?(node, CONSTANT_PATH_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.target.location)
      end

      sig { params(node: YARP::LocalVariableWriteNode).void }
      def on_local_variable_write(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::KeywordParameterNode).void }
      def on_keyword_parameter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::RestParameterNode).void }
      def on_rest_parameter(node)
        return unless matches?(node, LOCAL_NODES)

        name_loc = node.name_loc
        add_highlight(Constant::DocumentHighlightKind::WRITE, name_loc) if name_loc
      end

      sig { params(node: YARP::OptionalParameterNode).void }
      def on_optional_parameter(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::KeywordRestParameterNode).void }
      def on_keyword_rest_parameter(node)
        return unless matches?(node, LOCAL_NODES)

        name_loc = node.name_loc
        add_highlight(Constant::DocumentHighlightKind::WRITE, name_loc) if name_loc
      end

      sig { params(node: YARP::LocalVariableAndWriteNode).void }
      def on_local_variable_and_write(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::LocalVariableOperatorWriteNode).void }
      def on_local_variable_operator_write(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::LocalVariableOrWriteNode).void }
      def on_local_variable_or_write(node)
        return unless matches?(node, LOCAL_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::ClassVariableWriteNode).void }
      def on_class_variable_write(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::ClassVariableOrWriteNode).void }
      def on_class_variable_or_write(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::ClassVariableOperatorWriteNode).void }
      def on_class_variable_operator_write(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::ClassVariableAndWriteNode).void }
      def on_class_variable_and_write(node)
        return unless matches?(node, CLASS_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::ConstantWriteNode).void }
      def on_constant_write(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::ConstantOrWriteNode).void }
      def on_constant_or_write(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::ConstantOperatorWriteNode).void }
      def on_constant_operator_write(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::InstanceVariableWriteNode).void }
      def on_instance_variable_write(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::InstanceVariableOrWriteNode).void }
      def on_instance_variable_or_write(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::InstanceVariableAndWriteNode).void }
      def on_instance_variable_and_write(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::InstanceVariableOperatorWriteNode).void }
      def on_instance_variable_operator_write(node)
        return unless matches?(node, INSTANCE_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::ConstantAndWriteNode).void }
      def on_constant_and_write(node)
        return unless matches?(node, CONSTANT_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::GlobalVariableWriteNode).void }
      def on_global_variable_write(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::GlobalVariableOrWriteNode).void }
      def on_global_variable_or_write(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::GlobalVariableAndWriteNode).void }
      def on_global_variable_and_write(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      sig { params(node: YARP::GlobalVariableOperatorWriteNode).void }
      def on_global_variable_operator_write(node)
        return unless matches?(node, GLOBAL_VARIABLE_NODES)

        add_highlight(Constant::DocumentHighlightKind::WRITE, node.name_loc)
      end

      private

      sig { params(node: YARP::Node, classes: T::Array[T.class_of(YARP::Node)]).returns(T.nilable(T::Boolean)) }
      def matches?(node, classes)
        classes.any? { |klass| @target.is_a?(klass) } && @target_value == node_value(node)
      end

      sig { params(kind: Integer, location: YARP::Location).void }
      def add_highlight(kind, location)
        @_response << Interface::DocumentHighlight.new(range: range_from_location(location), kind: kind)
      end

      sig { params(node: T.nilable(YARP::Node)).returns(T.nilable(String)) }
      def node_value(node)
        case node
        when YARP::ConstantReadNode, YARP::ConstantPathNode, YARP::BlockArgumentNode, YARP::ConstantTargetNode,
          YARP::ConstantPathWriteNode, YARP::ConstantPathTargetNode, YARP::ConstantPathOrWriteNode,
          YARP::ConstantPathOperatorWriteNode, YARP::ConstantPathAndWriteNode
          node.slice
        when YARP::GlobalVariableReadNode, YARP::GlobalVariableAndWriteNode, YARP::GlobalVariableOperatorWriteNode,
          YARP::GlobalVariableOrWriteNode, YARP::GlobalVariableTargetNode, YARP::GlobalVariableWriteNode,
          YARP::InstanceVariableAndWriteNode, YARP::InstanceVariableOperatorWriteNode,
          YARP::InstanceVariableOrWriteNode, YARP::InstanceVariableReadNode, YARP::InstanceVariableTargetNode,
          YARP::InstanceVariableWriteNode, YARP::ConstantAndWriteNode, YARP::ConstantOperatorWriteNode,
          YARP::ConstantOrWriteNode, YARP::ConstantWriteNode, YARP::ClassVariableAndWriteNode,
          YARP::ClassVariableOperatorWriteNode, YARP::ClassVariableOrWriteNode, YARP::ClassVariableReadNode,
          YARP::ClassVariableTargetNode, YARP::ClassVariableWriteNode, YARP::LocalVariableAndWriteNode,
          YARP::LocalVariableOperatorWriteNode, YARP::LocalVariableOrWriteNode, YARP::LocalVariableReadNode,
          YARP::LocalVariableTargetNode, YARP::LocalVariableWriteNode, YARP::DefNode, YARP::BlockParameterNode,
          YARP::KeywordParameterNode, YARP::KeywordRestParameterNode, YARP::OptionalParameterNode,
          YARP::RequiredParameterNode, YARP::RestParameterNode

          node.name.to_s
        when YARP::CallNode
          node.message
        when YARP::ClassNode, YARP::ModuleNode
          node.constant_path.slice
        end
      end
    end
  end
end
