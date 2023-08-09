# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class HighlightTarget
        extend T::Sig

        READ = Constant::DocumentHighlightKind::READ
        WRITE = Constant::DocumentHighlightKind::WRITE

        class HighlightMatch
          extend T::Sig

          sig { returns(Integer) }
          attr_reader :type

          sig { returns(YARP::Node) }
          attr_reader :node

          sig { params(type: Integer, node: YARP::Node).void }
          def initialize(type:, node:)
            @type = type
            @node = node
          end
        end

        sig { params(node: YARP::Node).void }
        def initialize(node)
          @node = node
          @value = T.let(value(node), T.nilable(String))
        end

        sig { params(other: YARP::Node).returns(T.nilable(HighlightMatch)) }
        def highlight_type(other)
          matched_highlight(other) if other.is_a?(YARP::ParametersNode) || (@value && @value == value(other))
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
              HighlightMatch.new(type: READ, node: other)
            when YARP::DefNode
              HighlightMatch.new(type: WRITE, node: other.name)
            end
          # Variables, parameters and constants
          when YARP::GlobalVariableReadNode, YARP::InstanceVariableReadNode, YARP::ConstantReadNode, YARP::ClassVariableReadNode, SyntaxTree::VarField,
               # SyntaxTree::VarRef, SyntaxTree::Ident,
               YARP::GlobalVariableReadNode
            case other
            # when SyntaxTree::VarField
            #   HighlightMatch.new(type: WRITE, node: other)
            # when SyntaxTree::VarRef
            #   HighlightMatch.new(type: READ, node: other)
            when YARP::ClassNode, YARP::ModuleNode
              HighlightMatch.new(type: WRITE, node: other.location)
            when YARP::ConstantPathNode
              HighlightMatch.new(type: READ, node: other.location)
            when YARP::ParametersNode
              params = other.child_nodes.compact
              match = params.find { |param| value(param) == @value }
              HighlightMatch.new(type: WRITE, node: match) if match
            end
          end
        end

        sig { params(node: YARP::Node).returns(T.nilable(String)) }
        def value(node)
          case node
          when YARP::ConstantPathNode, YARP::ConstantPathNode # , SyntaxTree::TopConstField
            node.location.slice
          when YARP::GlobalVariableReadNode, YARP::InstanceVariableReadNode, YARP::ConstantReadNode, YARP::ClassVariableReadNode # , SyntaxTree::VarField,
            node.location.slice
          when YARP::DefNode, YARP::RestParameterNode,
               YARP::KeywordRestParameterNode, YARP::BlockArgumentNode
            node.name&.value
          # when SyntaxTree::VarField, SyntaxTree::VarRef, SyntaxTree::VCall
          #   value = node.value
          #   value.value unless value.nil? || value.is_a?(Symbol)
          when YARP::CallNode
            node.message
          when YARP::ClassNode, YARP::ModuleNode,
            node.location.slice
          end
        end
      end
    end
  end
end
