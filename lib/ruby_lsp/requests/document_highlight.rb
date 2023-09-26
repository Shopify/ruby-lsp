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

      READ = Constant::DocumentHighlightKind::READ
      WRITE = Constant::DocumentHighlightKind::WRITE

      class Highlight
        extend T::Sig

        sig { returns(Integer) }
        attr_reader :kind

        sig { returns(YARP::Location) }
        attr_reader :location

        sig { params(kind: Integer, location: YARP::Location).void }
        def initialize(kind:, location:)
          @kind = kind
          @location = location
        end
      end

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
          when YARP::ConstantAndWriteNode, YARP::ConstantOperatorWriteNode,
            YARP::ConstantOrWriteNode, YARP::ConstantPathAndWriteNode, YARP::ConstantPathNode,
            YARP::ConstantPathOperatorWriteNode, YARP::ConstantPathOrWriteNode, YARP::ConstantPathTargetNode,
            YARP::ConstantPathWriteNode, YARP::ConstantReadNode, YARP::ConstantTargetNode, YARP::ConstantWriteNode,
            YARP::LocalVariableAndWriteNode, YARP::LocalVariableOperatorWriteNode, YARP::LocalVariableOrWriteNode,
            YARP::LocalVariableReadNode, YARP::LocalVariableTargetNode, YARP::LocalVariableWriteNode, YARP::CallNode,
            YARP::BlockParameterNode, YARP::KeywordParameterNode, YARP::KeywordRestParameterNode,
            YARP::OptionalParameterNode, YARP::RequiredParameterNode, YARP::RestParameterNode
            HighlightTarget.new(target)
          end

        @target = T.let(highlight_target, T.nilable(HighlightTarget))

        emitter.register(self, :on_node) if @target
      end

      sig { params(node: T.nilable(YARP::Node)).void }
      def on_node(node)
        return if node.nil?

        match = T.must(@target).highlight_type(node)
        add_highlight(match) if match
      end

      sig do
        type_parameters(:ResponseType)
        .params(
          target: T.nilable(YARP::Node),
          parent: T.nilable(YARP::Node),
          emitter: EventEmitter,
          message_queue: Thread::Queue,
        ).returns(Listener[T::Array[Interface::DocumentHighlight]])
      end
      def self.for(target, parent, emitter, message_queue)
        case target
        when YARP::ClassVariableReadNode, YARP::ClassVariableTargetNode, YARP::ClassVariableWriteNode, YARP::ClassVariableAndWriteNode, YARP::ClassVariableOrWriteNode, YARP::ClassVariableOperatorWriteNode
          ClassVariableHighlight.new(emitter, message_queue, target.name)
        when YARP::GlobalVariableReadNode, YARP::GlobalVariableTargetNode, YARP::GlobalVariableWriteNode, YARP::GlobalVariableAndWriteNode, YARP::GlobalVariableOrWriteNode, YARP::GlobalVariableOperatorWriteNode
          GlobalVariableHighlight.new(emitter, message_queue, target.name)
        when YARP::InstanceVariableReadNode, YARP::InstanceVariableTargetNode, YARP::InstanceVariableWriteNode, YARP::InstanceVariableAndWriteNode, YARP::InstanceVariableOrWriteNode, YARP::InstanceVariableOperatorWriteNode
          InstanceVariableHighlight.new(emitter, message_queue, target.name)
        else
          new(target, parent, emitter, message_queue)
        end
      end

      class HighlightListener < Listener
        extend T::Sig

        ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

        sig { override.returns(ResponseType) }
        attr_reader :_response

        sig { params(emitter: EventEmitter, message_queue: Thread::Queue).void }
        def initialize(emitter, message_queue)
          super(emitter, message_queue)
          @_response = T.let([], ResponseType)
        end

        private

        sig { params(highlight: Highlight).void }
        def add_highlight(highlight)
          range = range_from_location(highlight.location)
          @_response << Interface::DocumentHighlight.new(range: range, kind: highlight.kind)
        end
      end

      class ClassVariableHighlight < HighlightListener
        extend T::Sig

        ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

        sig { returns(Symbol) }
        attr_reader :name

        sig { params(emitter: EventEmitter, message_queue: Thread::Queue, name: Symbol).void }
        def initialize(emitter, message_queue, name)
          super(emitter, message_queue)
          @name = T.let(name, Symbol)

          emitter.register(
            self,
            :on_class_variable_read,
            :on_class_variable_target,
            :on_class_variable_write,
            :on_class_variable_and_write,
            :on_class_variable_or_write,
            :on_class_variable_operator_write
          )
        end

        sig { params(node: YARP::ClassVariableReadNode).void }
        def on_class_variable_read(node)
          add_highlight(Highlight.new(kind: READ, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::ClassVariableTargetNode).void }
        def on_class_variable_target(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::ClassVariableWriteNode).void }
        def on_class_variable_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::ClassVariableAndWriteNode).void }
        def on_class_variable_and_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::ClassVariableOrWriteNode).void }
        def on_class_variable_or_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::ClassVariableOperatorWriteNode).void }
        def on_class_variable_operator_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end
      end

      class GlobalVariableHighlight < HighlightListener
        extend T::Sig

        ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

        sig { returns(Symbol) }
        attr_reader :name

        sig { params(emitter: EventEmitter, message_queue: Thread::Queue, name: Symbol).void }
        def initialize(emitter, message_queue, name)
          super(emitter, message_queue)
          @name = T.let(name, Symbol)

          emitter.register(
            self,
            :on_global_variable_read,
            :on_global_variable_target,
            :on_global_variable_write,
            :on_global_variable_and_write,
            :on_global_variable_or_write,
            :on_global_variable_operator_write
          )
        end

        sig { params(node: YARP::GlobalVariableReadNode).void }
        def on_global_variable_read(node)
          add_highlight(Highlight.new(kind: READ, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::GlobalVariableTargetNode).void }
        def on_global_variable_target(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::GlobalVariableWriteNode).void }
        def on_global_variable_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::GlobalVariableAndWriteNode).void }
        def on_global_variable_and_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::GlobalVariableOrWriteNode).void }
        def on_global_variable_or_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::GlobalVariableOperatorWriteNode).void }
        def on_global_variable_operator_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end
      end

      class InstanceVariableHighlight < HighlightListener
        extend T::Sig

        ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

        sig { returns(Symbol) }
        attr_reader :name

        sig { params(emitter: EventEmitter, message_queue: Thread::Queue, name: Symbol).void }
        def initialize(emitter, message_queue, name)
          super(emitter, message_queue)
          @name = T.let(name, Symbol)

          emitter.register(
            self,
            :on_instance_variable_read,
            :on_instance_variable_target,
            :on_instance_variable_write,
            :on_instance_variable_and_write,
            :on_instance_variable_or_write,
            :on_instance_variable_operator_write
          )
        end

        sig { params(node: YARP::InstanceVariableReadNode).void }
        def on_instance_variable_read(node)
          add_highlight(Highlight.new(kind: READ, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::InstanceVariableTargetNode).void }
        def on_instance_variable_target(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.location)) if node.name == name
        end

        sig { params(node: YARP::InstanceVariableWriteNode).void }
        def on_instance_variable_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::InstanceVariableAndWriteNode).void }
        def on_instance_variable_and_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::InstanceVariableOrWriteNode).void }
        def on_instance_variable_or_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end

        sig { params(node: YARP::InstanceVariableOperatorWriteNode).void }
        def on_instance_variable_operator_write(node)
          add_highlight(Highlight.new(kind: WRITE, location: node.name_loc)) if node.name == name
        end
      end

      private

      sig { params(highlight: Highlight).void }
      def add_highlight(highlight)
        range = range_from_location(highlight.location)
        @_response << Interface::DocumentHighlight.new(range: range, kind: highlight.kind)
      end

      class HighlightTarget
        extend T::Sig

        sig { params(node: YARP::Node).void }
        def initialize(node)
          @node = node
          @value = T.let(value(node), T.nilable(String))
        end

        sig { params(other: YARP::Node).returns(T.nilable(Highlight)) }
        def highlight_type(other)
          matched_highlight(other) if @value && @value == value(other)
        end

        private

        # Match the target type (where the cursor is positioned) with the `other` type (the node we're currently
        # visiting)
        sig { params(other: YARP::Node).returns(T.nilable(Highlight)) }
        def matched_highlight(other)
          case @node
          # Method definitions and invocations
          when YARP::CallNode, YARP::DefNode
            case other
            when YARP::CallNode
              Highlight.new(kind: READ, location: other.location)
            when YARP::DefNode
              Highlight.new(kind: WRITE, location: other.name_loc)
            end
          # Variables, parameters and constants
          else
            case other
            when YARP::ConstantPathTargetNode,
              YARP::ConstantTargetNode, YARP::LocalVariableTargetNode,
              YARP::BlockParameterNode, YARP::RequiredParameterNode

              Highlight.new(kind: WRITE, location: other.location)
            when YARP::LocalVariableWriteNode, YARP::KeywordParameterNode, YARP::RestParameterNode,
              YARP::OptionalParameterNode, YARP::KeywordRestParameterNode, YARP::LocalVariableAndWriteNode,
              YARP::LocalVariableOperatorWriteNode, YARP::LocalVariableOrWriteNode, YARP::ConstantWriteNode, YARP::ConstantOrWriteNode, YARP::ConstantOperatorWriteNode,
              YARP::ConstantAndWriteNode

              Highlight.new(kind: WRITE, location: T.must(other.name_loc)) if other.name
            when YARP::ConstantPathWriteNode, YARP::ConstantPathOrWriteNode, YARP::ConstantPathAndWriteNode,
              YARP::ConstantPathOperatorWriteNode

              Highlight.new(kind: WRITE, location: other.target.location)
            when YARP::LocalVariableReadNode, YARP::ConstantPathNode, YARP::ConstantReadNode

              Highlight.new(kind: READ, location: other.location)
            when YARP::ClassNode, YARP::ModuleNode
              Highlight.new(kind: WRITE, location: other.constant_path.location)
            end
          end
        end

        sig { params(node: YARP::Node).returns(T.nilable(String)) }
        def value(node)
          case node
          when YARP::ConstantReadNode, YARP::ConstantPathNode, YARP::BlockArgumentNode, YARP::ConstantTargetNode,
            YARP::ConstantPathWriteNode, YARP::ConstantPathTargetNode, YARP::ConstantPathOrWriteNode,
            YARP::ConstantPathOperatorWriteNode, YARP::ConstantPathAndWriteNode
            node.slice
          when YARP::ConstantAndWriteNode, YARP::ConstantOperatorWriteNode,
            YARP::ConstantOrWriteNode, YARP::ConstantWriteNode, YARP::LocalVariableAndWriteNode,
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
end
