# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/document_symbol"

module RubyLsp
  module Requests
    # The [document
    # symbol](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentSymbol) request
    # informs the editor of all the important symbols, such as classes, variables, and methods, defined in a file. With
    # this information, the editor can populate breadcrumbs, file outline and allow for fuzzy symbol searches.
    #
    # In VS Code, symbol search known as 'Go To Symbol in Editor' and can be accessed with Ctrl/Cmd-Shift-O,
    # or by opening the command palette and inserting an `@` symbol.
    class DocumentSymbol < Request
      class << self
        #: -> Interface::DocumentSymbolOptions
        def provider
          Interface::DocumentSymbolOptions.new
        end
      end

      #: (URI::Generic uri, (RubyDocument | ERBDocument) document, Prism::Dispatcher dispatcher) -> void
      def initialize(uri, document, dispatcher)
        super()
        @response_builder = ResponseBuilders::DocumentSymbol.new(document.encoding, document.parse_result) #: ResponseBuilders::DocumentSymbol
        Listeners::DocumentSymbol.new(@response_builder, uri, dispatcher)

        Addon.addons.each do |addon|
          addon.create_document_symbol_listener(@response_builder, dispatcher)
        end
      end

      # @override
      #: -> Array[Interface::DocumentSymbol]
      def perform
        @response_builder.response
      end
    end
  end
end
