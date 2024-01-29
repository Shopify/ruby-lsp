# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/document_symbol"

module RubyLsp
  module Requests
    # ![Document symbol demo](../../document_symbol.gif)
    #
    # The [document
    # symbol](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentSymbol) request
    # informs the editor of all the important symbols, such as classes, variables, and methods, defined in a file. With
    # this information, the editor can populate breadcrumbs, file outline and allow for fuzzy symbol searches.
    #
    # In VS Code, fuzzy symbol search can be accessed by opening the command palette and inserting an `@` symbol.
    #
    # # Example
    #
    # ```ruby
    # class Person # --> document symbol: class
    #   attr_reader :age # --> document symbol: field
    #
    #   def initialize
    #     @age = 0 # --> document symbol: variable
    #   end
    #
    #   def age # --> document symbol: method
    #   end
    # end
    # ```
    class DocumentSymbol < Request
      extend T::Sig

      class << self
        extend T::Sig

        sig { returns(Interface::DocumentSymbolClientCapabilities) }
        def provider
          Interface::DocumentSymbolClientCapabilities.new(
            hierarchical_document_symbol_support: true,
            symbol_kind: {
              value_set: (Constant::SymbolKind::FILE..Constant::SymbolKind::TYPE_PARAMETER).to_a,
            },
          )
        end
      end

      sig { params(dispatcher: Prism::Dispatcher).void }
      def initialize(dispatcher)
        super()
        @response_builder = T.let(ResponseBuilders::DocumentSymbol.new, ResponseBuilders::DocumentSymbol)
        Listeners::DocumentSymbol.new(@response_builder, dispatcher)

        Addon.addons.each do |addon|
          addon.create_document_symbol_listener(@response_builder, dispatcher)
        end
      end

      sig { override.returns(T::Array[Interface::DocumentSymbol]) }
      def perform
        @response_builder.response
      end
    end
  end
end
