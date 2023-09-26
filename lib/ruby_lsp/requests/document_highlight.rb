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

      private

      sig { params(match: HighlightTarget::HighlightMatch).void }
      def add_highlight(match)
        range = range_from_location(match.location)
        @_response << Interface::DocumentHighlight.new(range: range, kind: match.type)
      end

      class HighlightTarget
        extend T::Sig

        READ = Constant::DocumentHighlightKind::READ
        WRITE = Constant::DocumentHighlightKind::WRITE

        class HighlightMatch
          extend T::Sig

          sig { returns(Integer) }
          attr_reader :type

          sig { returns(YARP::Location) }
          attr_reader :location

          sig { params(type: Integer, location: YARP::Location).void }
          def initialize(type:, location:)
            @type = type
            @location = location
          end
        end

        sig { params(node: YARP::Node).void }
        def initialize(node)
          @node = node
          @value = T.let(value(node), T.nilable(String))
        end

        sig { params(other: YARP::Node).returns(T.nilable(HighlightMatch)) }
        def highlight_type(other)
          matched_highlight(other) if @value && @value == value(other)
        end

        private

        # Match the target type (where the cursor is positioned) with the `other` type (the node we're currently
        # visiting)
        sig { params(other: YARP::Node).returns(T.nilable(HighlightMatch)) }
        def matched_highlight(other)
          case @node
          # Method definitions and invocations
          when YARP::CallNode, YARP::DefNode
            case other
            when YARP::CallNode
              HighlightMatch.new(type: READ, location: other.location)
            when YARP::DefNode
              HighlightMatch.new(type: WRITE, location: other.name_loc)
            end
          # Variables, parameters and constants
          else
            case other
            when YARP::GlobalVariableTargetNode, YARP::InstanceVariableTargetNode, YARP::ConstantPathTargetNode,
              YARP::ConstantTargetNode, YARP::ClassVariableTargetNode, YARP::LocalVariableTargetNode,
              YARP::BlockParameterNode, YARP::RequiredParameterNode

              HighlightMatch.new(type: WRITE, location: other.location)
            when YARP::LocalVariableWriteNode, YARP::KeywordParameterNode, YARP::RestParameterNode,
              YARP::OptionalParameterNode, YARP::KeywordRestParameterNode, YARP::LocalVariableAndWriteNode,
              YARP::LocalVariableOperatorWriteNode, YARP::LocalVariableOrWriteNode, YARP::ClassVariableWriteNode,
              YARP::ClassVariableOrWriteNode, YARP::ClassVariableOperatorWriteNode, YARP::ClassVariableAndWriteNode,
              YARP::ConstantWriteNode, YARP::ConstantOrWriteNode, YARP::ConstantOperatorWriteNode,
              YARP::InstanceVariableWriteNode, YARP::ConstantAndWriteNode, YARP::InstanceVariableOrWriteNode,
              YARP::InstanceVariableAndWriteNode, YARP::InstanceVariableOperatorWriteNode,
              YARP::GlobalVariableWriteNode, YARP::GlobalVariableOrWriteNode, YARP::GlobalVariableAndWriteNode,
              YARP::GlobalVariableOperatorWriteNode

              HighlightMatch.new(type: WRITE, location: T.must(other.name_loc)) if other.name
            when YARP::ConstantPathWriteNode, YARP::ConstantPathOrWriteNode, YARP::ConstantPathAndWriteNode,
              YARP::ConstantPathOperatorWriteNode

              HighlightMatch.new(type: WRITE, location: other.target.location)
            when YARP::LocalVariableReadNode, YARP::ConstantPathNode, YARP::ConstantReadNode,
              YARP::InstanceVariableReadNode, YARP::ClassVariableReadNode, YARP::GlobalVariableReadNode

              HighlightMatch.new(type: READ, location: other.location)
            when YARP::ClassNode, YARP::ModuleNode
              HighlightMatch.new(type: WRITE, location: other.constant_path.location)
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
end
