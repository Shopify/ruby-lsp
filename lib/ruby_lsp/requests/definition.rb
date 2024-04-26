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
          global_state: GlobalState,
          position: T::Hash[Symbol, T.untyped],
          dispatcher: Prism::Dispatcher,
          typechecker_enabled: T::Boolean,
        ).void
      end
      def initialize(document, global_state, position, dispatcher, typechecker_enabled)
        super()
        @response_builder = T.let(
          ResponseBuilders::CollectionResponseBuilder[Interface::Location].new,
          ResponseBuilders::CollectionResponseBuilder[Interface::Location],
        )
        @dispatcher = dispatcher

        target, parent, nesting = document.locate_node(
          position,
          node_types: [Prism::CallNode, Prism::ConstantReadNode, Prism::ConstantPathNode],
        )

        if target.is_a?(Prism::ConstantReadNode) && parent.is_a?(Prism::ConstantPathNode)
          # If the target is part of a constant path node, we need to find the exact portion of the constant that the
          # user is requesting to go to definition for
          target = determine_target(
            target,
            parent,
            position,
          )
        elsif target.is_a?(Prism::CallNode) && target.name != :require && target.name != :require_relative &&
            !covers_position?(target.message_loc, position)
          # If the target is a method call, we need to ensure that the requested position is exactly on top of the
          # method identifier. Otherwise, we risk showing definitions for unrelated things
          target = nil
        end

        if target
          Listeners::Definition.new(
            @response_builder,
            global_state,
            document.uri,
            nesting,
            dispatcher,
            typechecker_enabled,
          )

          Addon.addons.each do |addon|
            addon.create_definition_listener(@response_builder, document.uri, nesting, dispatcher)
          end
        end

        @target = T.let(target, T.nilable(Prism::Node))
      end

      sig { override.returns(T::Array[Interface::Location]) }
      def perform
        @dispatcher.dispatch_once(@target) if @target
        @response_builder.response
      end
    end
  end
end
