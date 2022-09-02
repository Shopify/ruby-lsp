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
    #
    # foo(positional_arg, key: value)
    # #                  ^          ^ these two locations will have brace labels added
    # ```
    class InlayHints < BaseRequest
      RESCUE_STRING_LENGTH = T.let("rescue".length, Integer)

      sig { params(document: Document, range: T::Range[Integer]).void }
      def initialize(document, range)
        super(document)

        @hints = T.let([], T::Array[LanguageServer::Protocol::Interface::InlayHint])
        @range = range
      end

      sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Interface::InlayHint], Object)) }
      def run
        visit(@document.tree)
        @hints
      end

      sig { params(node: SyntaxTree::Rescue).void }
      def visit_rescue(node)
        return unless node.exception.nil?

        loc = node.location
        return unless visible?(loc)

        @hints << LanguageServer::Protocol::Interface::InlayHint.new(
          position: { line: loc.start_line - 1, character: loc.start_column + RESCUE_STRING_LENGTH },
          label: "StandardError",
          padding_left: true,
          tooltip: "StandardError is implied in a bare rescue",
        )

        super
      end

      sig { params(node: SyntaxTree::Args).void }
      def visit_args(node)
        bare_assoc_hash = node.parts.find { |x| x.is_a?(SyntaxTree::BareAssocHash) }
        return unless bare_assoc_hash

        loc = bare_assoc_hash.location
        return unless visible?(loc)

        @hints << LanguageServer::Protocol::Interface::InlayHint.new(
          position: {
            line: bare_assoc_hash.assocs.first.location.start_line - 1,
            character: bare_assoc_hash.assocs.first.location.start_column,
          },
          label: "{",
          padding_right: true,
          tooltip: "Braces are implied, this is where the left brace would be",
        )

        @hints << LanguageServer::Protocol::Interface::InlayHint.new(
          position: {
            line: bare_assoc_hash.assocs.last.location.end_line - 1,
            character: bare_assoc_hash.assocs.last.location.end_column,
          },
          label: "}",
          padding_left: true,
          tooltip: "Braces are implied, this is where the right brace would be",
        )

        super
      end

      private

      sig { params(loc: SyntaxTree::Location).returns(T::Boolean) }
      def visible?(loc)
        @range.cover?(loc.start_line - 1) && @range.cover?(loc.end_line - 1)
      end
    end
  end
end
