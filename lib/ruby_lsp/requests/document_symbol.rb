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
      extend T::Generic

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

      ResponseType = type_member { { fixed: T::Array[Interface::DocumentSymbol] } }

      sig { params(dispatcher: Prism::Dispatcher).void }
      def initialize(dispatcher)
        super()
        @listeners = T.let(
          [Listeners::DocumentSymbol.new(dispatcher)],
          T::Array[Listener[ResponseType]],
        )

        Addon.addons.each do |addon|
          addon_listener = addon.create_document_symbol_listener(dispatcher)
          @listeners << addon_listener if addon_listener
        end
      end

      sig { override.returns(ResponseType) }
      def perform
        @listeners.flat_map(&:response).compact
      end
    end
  end
end
