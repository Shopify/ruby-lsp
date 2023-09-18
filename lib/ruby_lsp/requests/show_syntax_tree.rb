# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Show syntax tree demo](../../show_syntax_tree.gif)
    #
    # Show syntax tree is a custom [LSP
    # request](https://microsoft.github.io/language-server-protocol/specification#requestMessage) that displays the AST
    # for the current document or for the current selection in a new tab.
    #
    # # Example
    #
    # ```ruby
    # # Executing the Ruby LSP: Show syntax tree command will display the AST for the document
    # 1 + 1
    # # (program (statements ((binary (int "1") + (int "1")))))
    # ```
    #
    class ShowSyntaxTree < BaseRequest
      extend T::Sig

      sig { params(document: Document, range: T.nilable(Document::RangeShape)).void }
      def initialize(document, range)
        super(document)

        @range = range
      end

      sig { override.returns(String) }
      def run
        return ast_for_range if @range

        output_string = +""
        PP.pp(@document.tree, output_string)
        output_string
      end

      private

      sig { returns(String) }
      def ast_for_range
        range = T.must(@range)

        scanner = @document.create_scanner
        start_char = scanner.find_char_position(range[:start])
        end_char = scanner.find_char_position(range[:end])

        queue = @document.tree.statements.body.dup
        found_nodes = []

        until queue.empty?
          node = queue.shift
          next unless node

          loc = node.location

          # If the node is fully covered by the selection, then we found one of the nodes to be displayed and don't want
          # to continue descending into its children
          if (start_char..end_char).cover?(loc.start_offset..loc.end_offset)
            found_nodes << node
          else
            T.unsafe(queue).unshift(*node.child_nodes)
          end
        end

        found_nodes.map do |node|
          output_string = +""
          PP.pp(node, output_string)
          output_string
        end.join("\n")
      end
    end
  end
end
