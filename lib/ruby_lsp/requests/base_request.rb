# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # :nodoc:
    class BaseRequest < SyntaxTree::Visitor
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { params(document: Document).void }
      def initialize(document)
        @document = document

        # Parsing the document here means we're taking a lazy approach by only doing it when the first feature request
        # is received by the server. This happens because {Document#parse} remembers if there are new edits to be parsed
        @document.parse

        super()
      end

      sig { abstract.returns(Object) }
      def run; end

      sig { params(node: SyntaxTree::Node).returns(LanguageServer::Protocol::Interface::Range) }
      def range_from_syntax_tree_node(node)
        loc = node.location

        LanguageServer::Protocol::Interface::Range.new(
          start: LanguageServer::Protocol::Interface::Position.new(line: loc.start_line - 1,
            character: loc.start_column),
          end: LanguageServer::Protocol::Interface::Position.new(line: loc.end_line - 1, character: loc.end_column),
        )
      end

      sig { params(node: SyntaxTree::ConstPathRef).returns(String) }
      def full_constant_name(node)
        name = +node.constant.value
        constant = T.let(node, SyntaxTree::Node)

        while constant.is_a?(SyntaxTree::ConstPathRef)
          constant = constant.parent

          case constant
          when SyntaxTree::ConstPathRef
            name.prepend("#{constant.constant.value}::")
          when SyntaxTree::VarRef
            name.prepend("#{constant.value.value}::")
          end
        end

        name
      end

      sig do
        params(
          parent: SyntaxTree::Node,
          target_nodes: T::Array[T.class_of(SyntaxTree::Node)],
          position: Integer,
        ).returns(T::Array[SyntaxTree::Node])
      end
      def locate_node_and_parent(parent, target_nodes, position)
        matched = parent.child_nodes.compact.bsearch do |child|
          if (child.location.start_char...child.location.end_char).cover?(position)
            0
          else
            position <=> child.location.start_char
          end
        end

        case matched
        when *target_nodes
          [matched, parent]
        when SyntaxTree::Node
          locate_node_and_parent(matched, target_nodes, position)
        else
          []
        end
      end
    end
  end
end
