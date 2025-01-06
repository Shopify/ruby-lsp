# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/completion"

module RubyLsp
  module Requests
    # The [completion](https://microsoft.github.io/language-server-protocol/specification#textDocument_completion)
    # suggests possible completions according to what the developer is typing.
    class Completion < Request
      extend T::Sig

      class << self
        extend T::Sig

        sig { returns(Interface::CompletionOptions) }
        def provider
          Interface::CompletionOptions.new(
            resolve_provider: true,
            trigger_characters: ["/", "\"", "'", ":", "@", ".", "=", "<", "$"],
            completion_item: {
              labelDetailsSupport: true,
            },
          )
        end
      end

      sig do
        params(
          document: T.any(RubyDocument, ERBDocument),
          global_state: GlobalState,
          params: T::Hash[Symbol, T.untyped],
          sorbet_level: RubyDocument::SorbetLevel,
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(document, global_state, params, sorbet_level, dispatcher)
        super()
        @target = T.let(nil, T.nilable(Prism::Node))
        @dispatcher = dispatcher
        # Completion always receives the position immediately after the character that was just typed. Here we adjust it
        # back by 1, so that we find the right node
        char_position, _ = document.find_index_by_position(params[:position])
        char_position -= 1
        delegate_request_if_needed!(global_state, document, char_position)

        node_context = RubyDocument.locate(
          document.parse_result.value,
          char_position,
          node_types: [
            Prism::CallNode,
            Prism::ConstantReadNode,
            Prism::ConstantPathNode,
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
            Prism::ClassVariableAndWriteNode,
            Prism::ClassVariableOperatorWriteNode,
            Prism::ClassVariableOrWriteNode,
            Prism::ClassVariableReadNode,
            Prism::ClassVariableTargetNode,
            Prism::ClassVariableWriteNode,
          ],
          code_units_cache: document.code_units_cache,
        )
        @response_builder = T.let(
          ResponseBuilders::CollectionResponseBuilder[Interface::CompletionItem].new,
          ResponseBuilders::CollectionResponseBuilder[Interface::CompletionItem],
        )

        Listeners::Completion.new(
          @response_builder,
          global_state,
          node_context,
          sorbet_level,
          dispatcher,
          document.uri,
          params.dig(:context, :triggerCharacter),
        )

        Addon.addons.each do |addon|
          addon.create_completion_listener(@response_builder, node_context, dispatcher, document.uri)
        end

        matched = node_context.node
        parent = node_context.parent
        return unless matched && parent

        @target = if parent.is_a?(Prism::ConstantPathNode) && matched.is_a?(Prism::ConstantReadNode)
          parent
        else
          matched
        end
      end

      sig { override.returns(T::Array[Interface::CompletionItem]) }
      def perform
        return [] unless @target

        @dispatcher.dispatch_once(@target)
        @response_builder.response
      end
    end
  end
end
