# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Inlay hint demo](../../misc/inlay_hint.gif)
    #
    # [Inlay hints](https://microsoft.github.io/language-server-protocol/specification#textDocument_inlayHint)
    # are labels added directly in the code that explicitly show the user something that might
    # otherwise just be implied.
    #
    # # Example
    #
    # ```ruby
    # begin
    #   puts "do something that might raise"
    # rescue # Label "StandardError" goes here as a bare rescue implies rescuing StandardError
    #   puts "handle some rescue"
    # end
    # ```
    class InlayHints < BaseRequest
      RESCUE_STRING_LENGTH = T.let("rescue".length, Integer)

      sig { params(document: Document, range: T::Range[Integer]).void }
      def initialize(document, range)
        super(document)

        @hints = T.let([], T::Array[Interface::InlayHint])
        @range = range
      end

      sig { override.returns(T.all(T::Array[Interface::InlayHint], Object)) }
      def run
        visit(@document.tree) if @document.parsed?
        @hints
      end

      sig { override.params(node: SyntaxTree::Rescue).void }
      def visit_rescue(node)
        exception = node.exception
        return unless exception.nil? || exception.exceptions.nil?

        loc = node.location
        return unless visible?(node, @range)

        @hints << Interface::InlayHint.new(
          position: { line: loc.start_line - 1, character: loc.start_column + RESCUE_STRING_LENGTH },
          label: "StandardError",
          padding_left: true,
          tooltip: "StandardError is implied in a bare rescue",
        )

        super
      end
    end
  end
end
