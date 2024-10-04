# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/definition"

module RubyLsp
  module Requests
    # The [definition
    # request](https://microsoft.github.io/language-server-protocol/specification#textDocument_definition) jumps to the
    # definition of the symbol under the cursor.
    class Definition < Request
      extend T::Sig
      extend T::Generic

      SPECIAL_METHOD_CALLS = [
        :require,
        :require_relative,
        :autoload,
      ].freeze

      sig do
        params(
          document: T.any(RubyDocument, ERBDocument),
          global_state: GlobalState,
          position: T::Hash[Symbol, T.untyped],
          dispatcher: Prism::Dispatcher,
          sorbet_level: RubyDocument::SorbetLevel,
        ).void
      end
      def initialize(document, global_state, position, dispatcher, sorbet_level)
        super()
        @response_builder = T.let(
          ResponseBuilders::CollectionResponseBuilder[T.any(Interface::Location, Interface::LocationLink)].new,
          ResponseBuilders::CollectionResponseBuilder[T.any(Interface::Location, Interface::LocationLink)],
        )
        @dispatcher = dispatcher

        char_position = document.create_scanner.find_char_position(position)
        delegate_request_if_needed!(global_state, document, char_position)

        node_context = RubyDocument.locate(
          document.parse_result.value,
          char_position,
          node_types: [
            Prism::CallNode,
            Prism::ConstantReadNode,
            Prism::ConstantPathNode,
            Prism::BlockArgumentNode,
            Prism::InstanceVariableReadNode,
            Prism::InstanceVariableAndWriteNode,
            Prism::InstanceVariableOperatorWriteNode,
            Prism::InstanceVariableOrWriteNode,
            Prism::InstanceVariableTargetNode,
            Prism::InstanceVariableWriteNode,
            Prism::SymbolNode,
            Prism::StringNode,
            Prism::SuperNode,
            Prism::ForwardingSuperNode,
          ],
          encoding: global_state.encoding,
        )

        target = node_context.node
        parent = node_context.parent

        if target.is_a?(Prism::ConstantReadNode) && parent.is_a?(Prism::ConstantPathNode)
          # If the target is part of a constant path node, we need to find the exact portion of the constant that the
          # user is requesting to go to definition for
          target = determine_target(
            target,
            parent,
            position,
          )
        elsif target.is_a?(Prism::CallNode) && !SPECIAL_METHOD_CALLS.include?(target.message) && !covers_position?(
          target.message_loc, position
        )
          # If the target is a method call, we need to ensure that the requested position is exactly on top of the
          # method identifier. Otherwise, we risk showing definitions for unrelated things
          target = nil
        # For methods with block arguments using symbol-to-proc
        elsif target.is_a?(Prism::SymbolNode) && parent.is_a?(Prism::BlockArgumentNode)
          target = parent
        end

        if target
          Listeners::Definition.new(
            @response_builder,
            global_state,
            document.language_id,
            document.uri,
            node_context,
            dispatcher,
            sorbet_level,
          )

          Addon.addons.each do |addon|
            addon.create_definition_listener(@response_builder, document.uri, node_context, dispatcher)
          end
        end

        @target = T.let(target, T.nilable(Prism::Node))
      end

      sig { override.returns(T::Array[T.any(Interface::Location, Interface::LocationLink)]) }
      def perform
        @dispatcher.dispatch_once(@target) if @target
        @response_builder.response
      end
    end
  end
end
