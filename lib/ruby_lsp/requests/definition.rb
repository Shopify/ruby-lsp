# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/definition"

module RubyLsp
  module Requests
    # ![Definition demo](../../definition.gif)
    #
    # The [definition
    # request](https://microsoft.github.io/language-server-protocol/specification#textDocument_definition) jumps to the
    # definition of the symbol under the cursor.
    #
    # Currently supported targets:
    # - Classes
    # - Modules
    # - Constants
    # - Require paths
    # - Methods invoked on self only
    #
    # # Example
    #
    # ```ruby
    # require "some_gem/file" # <- Request go to definition on this string will take you to the file
    # Product.new # <- Request go to definition on this class name will take you to its declaration.
    # ```
    class Definition < Request
      extend T::Sig
      extend T::Generic

      sig do
        params(
          document: Document,
          index: RubyIndexer::Index,
          position: T::Hash[Symbol, T.untyped],
          dispatcher: Prism::Dispatcher,
          typechecker_enabled: T::Boolean,
        ).void
      end
      def initialize(document, index, position, dispatcher, typechecker_enabled)
        super()
        @response_builder = T.let(
          ResponseBuilders::CollectionResponseBuilder[Interface::Location].new,
          ResponseBuilders::CollectionResponseBuilder[Interface::Location],
        )

        target, parent, nesting = document.locate_node(
          position,
          node_types: [Prism::CallNode, Prism::ConstantReadNode, Prism::ConstantPathNode],
        )

        if target.is_a?(Prism::ConstantReadNode) && parent.is_a?(Prism::ConstantPathNode)
          target = determine_target(
            target,
            parent,
            position,
          )
        end

        Listeners::Definition.new(@response_builder, document.uri, nesting, index, dispatcher, typechecker_enabled)

        Addon.addons.each do |addon|
          addon.create_definition_listener(@response_builder, document.uri, nesting, index, dispatcher)
        end

        @target = T.let(target, T.nilable(Prism::Node))
        @dispatcher = dispatcher
      end

      sig { override.returns(T::Array[Interface::Location]) }
      def perform
        @dispatcher.dispatch_once(@target)
        @response_builder.response
      end
    end
  end
end
