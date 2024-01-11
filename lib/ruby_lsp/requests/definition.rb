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

      ResponseType = type_member { { fixed: T.nilable(T.any(T::Array[Interface::Location], Interface::Location)) } }

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
        target, parent, nesting = document.locate_node(
          position,
          node_types: [Prism::CallNode, Prism::ConstantReadNode, Prism::ConstantPathNode],
        )

        target = parent if target.is_a?(Prism::ConstantReadNode) && parent.is_a?(Prism::ConstantPathNode)

        @listeners = T.let(
          [Listeners::Definition.new(document.uri, nesting, index, dispatcher, typechecker_enabled)],
          T::Array[Listener[T.nilable(T.any(T::Array[Interface::Location], Interface::Location))]],
        )
        Addon.addons.each do |addon|
          addon_listener = addon.create_definition_listener(document.uri, nesting, index, dispatcher)
          @listeners << addon_listener if addon_listener
        end

        @target = T.let(target, T.nilable(Prism::Node))
        @dispatcher = dispatcher
      end

      sig { override.returns(ResponseType) }
      def response
        @dispatcher.dispatch_once(@target)
        result = []

        @listeners.each do |listener|
          res = listener.response
          case res
          when Interface::Location
            result << res
          when Array
            result.concat(res)
          end
        end

        result if result.any?
      end
    end
  end
end
