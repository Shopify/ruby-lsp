# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [document highlight](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentHighlight)
    # informs the editor all relevant elements of the currently pointed item for highlighting. For example, when
    # the cursor is on the `F` of the constant `FOO`, the editor should identify other occurences of `FOO`
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
    # ````
    class DocumentHighlight < BaseRequest
      def self.run(document, position)
        new(document, position).run
      end

      def initialize(document, position)
        position = Document::Scanner.new(document.source).find_position(position)
        @visitor = find(document.tree, position)

        super(document)
      end

      def run
        # no visitor means the target is not highlightable
        return [] unless @visitor

        @visitor.visit(@document.tree)
        @visitor.highlights
      end

      private

      def find(node, position)
        matched =
          node.child_nodes.compact.bsearch do |child|
            if (child.location.start_char...child.location.end_char).cover?(position)
              0
            else
              position <=> child.location.start_char
            end
          end

        case matched
        when SyntaxTree::GVar
          GVarHighlightVisitor.new(matched)
        when SyntaxTree::Ident
          IdentHighlightVisitor.new(matched)
        when SyntaxTree::IVar
          IVarHighlightVisitor.new(matched)
        when SyntaxTree::Const
          ConstHighlightVisitor.new(matched)
        when SyntaxTree::CVar
          CVarHighlightVisitor.new(matched)
        when SyntaxTree::Node
          find(matched, position)
        end
      end

      class HighlightVisitor < SyntaxTree::Visitor
        WRITE_KIND = 3
        READ_KIND = 2

        attr_reader :highlights

        def initialize(target_node)
          @highlights = []
          @target = target_node.value

          super()
        end

        def visit_var_field(node)
          highlight(node.value, WRITE_KIND) if matches_target?(node.value)
        end

        def visit_var_ref(node)
          highlight(node.value, READ_KIND) if matches_target?(node.value)
        end

        private

        def highlight(node, kind)
          range = range_from_syntax_tree_node(node)
          @highlights << LanguageServer::Protocol::Interface::DocumentHighlight.new(range: range, kind: kind)
        end

        def range_from_syntax_tree_node(node)
          loc = node.location

          LanguageServer::Protocol::Interface::Range.new(
            start: LanguageServer::Protocol::Interface::Position.new(line: loc.start_line - 1,
              character: loc.start_column),
            end: LanguageServer::Protocol::Interface::Position.new(line: loc.end_line - 1, character: loc.end_column),
          )
        end
      end

      class IVarHighlightVisitor < HighlightVisitor
        def matches_target?(node)
          node.is_a?(SyntaxTree::IVar) && node.value == @target
        end
      end

      class GVarHighlightVisitor < HighlightVisitor
        def matches_target?(node)
          node.is_a?(SyntaxTree::GVar) && node.value == @target
        end
      end

      class IdentHighlightVisitor < HighlightVisitor
        def matches_target?(node)
          node.is_a?(SyntaxTree::Ident) && node.value == @target
        end
      end

      class ConstHighlightVisitor < HighlightVisitor
        def matches_target?(node)
          node.is_a?(SyntaxTree::Const) && node.value == @target
        end
      end

      class CVarHighlightVisitor < HighlightVisitor
        def matches_target?(node)
          node.is_a?(SyntaxTree::CVar) && node.value == @target
        end
      end
    end
  end
end
