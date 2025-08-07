# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/definition"

module RubyLsp
  module Requests
    # The [definition
    # request](https://microsoft.github.io/language-server-protocol/specification#textDocument_definition) jumps to the
    # definition of the symbol under the cursor.
    class Definition < Request
      #: ((RubyDocument | ERBDocument) document, GlobalState global_state, Hash[Symbol, untyped] position, Prism::Dispatcher dispatcher, SorbetLevel sorbet_level) -> void
      def initialize(document, global_state, position, dispatcher, sorbet_level)
        super()
        @response_builder = ResponseBuilders::CollectionResponseBuilder
          .new #: ResponseBuilders::CollectionResponseBuilder[(Interface::Location | Interface::LocationLink)]
        @dispatcher = dispatcher

        char_position, _ = document.find_index_by_position(position)
        delegate_request_if_needed!(global_state, document, char_position)

        node_context = RubyDocument.locate(
          document.ast,
          char_position,
          node_types: [
            Prism::CallNode,
            Prism::ConstantReadNode,
            Prism::ConstantPathNode,
            Prism::BlockArgumentNode,
            Prism::GlobalVariableAndWriteNode,
            Prism::GlobalVariableOperatorWriteNode,
            Prism::GlobalVariableOrWriteNode,
            Prism::GlobalVariableReadNode,
            Prism::GlobalVariableTargetNode,
            Prism::GlobalVariableWriteNode,
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
            Prism::ClassVariableAndWriteNode,
            Prism::ClassVariableOperatorWriteNode,
            Prism::ClassVariableOrWriteNode,
            Prism::ClassVariableReadNode,
            Prism::ClassVariableTargetNode,
            Prism::ClassVariableWriteNode,
          ],
          code_units_cache: document.code_units_cache,
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
        elsif position_outside_target?(position, target)
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

        @target = target #: Prism::Node?
      end

      # @override
      #: -> Array[(Interface::Location | Interface::LocationLink)]
      def perform
        @dispatcher.dispatch_once(@target) if @target
        @response_builder.response
      end

      private

      #: (Hash[Symbol, untyped] position, Prism::Node? target) -> bool
      def position_outside_target?(position, target)
        case target
        when Prism::GlobalVariableAndWriteNode,
          Prism::GlobalVariableOperatorWriteNode,
          Prism::GlobalVariableOrWriteNode,
          Prism::GlobalVariableWriteNode,
          Prism::InstanceVariableAndWriteNode,
          Prism::InstanceVariableOperatorWriteNode,
          Prism::InstanceVariableOrWriteNode,
          Prism::InstanceVariableWriteNode

          !covers_position?(target.name_loc, position)
        when Prism::CallNode
          !covers_position?(target.message_loc, position)
        else
          false
        end
      end
    end
  end
end
