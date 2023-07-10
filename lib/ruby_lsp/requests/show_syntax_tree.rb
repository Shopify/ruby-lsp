# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Show syntax tree demo](../../show_syntax_tree.gif)
    #
    # Show syntax tree is a custom [LSP
    # request](https://microsoft.github.io/language-server-protocol/specification#requestMessage) that displays the AST
    # for the current document in a new tab.
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

      sig { override.returns(String) }
      def run
        return "Document contains syntax error" if @document.syntax_error?

        output_string = +""
        PP.pp(@document.tree, output_string)
        output_string
      end
    end
  end
end
