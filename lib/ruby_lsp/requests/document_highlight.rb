# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/document_highlight"

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
    class DocumentHighlight < Request
      extend T::Sig

      ResponseType = type_member { { fixed: T::Array[Interface::DocumentHighlight] } }

      sig do
        params(
          document: Document,
          position: T::Hash[Symbol, T.untyped],
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(document, position, dispatcher)
        super()
        target, parent = document.locate_node(position)
        @listener = T.let(Listeners::DocumentHighlight.new(target, parent, dispatcher), Listener[ResponseType])
      end

      sig { override.returns(ResponseType) }
      def response
        @listener.response
      end
    end
  end
end
