# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/completion"

module RubyLsp
  module Requests
    # ![Completion demo](../../completion.gif)
    #
    # The [completion](https://microsoft.github.io/language-server-protocol/specification#textDocument_completion)
    # suggests possible completions according to what the developer is typing.
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
    # require "ruby_lsp/requests" # --> completion: suggests `base_request`, `code_actions`, ...
    #
    # RubyLsp::Requests:: # --> completion: suggests `Completion`, `Hover`, ...
    # ```
    class Completion < Request
      extend T::Sig
      extend T::Generic

      class << self
        extend T::Sig

        sig { returns(Interface::CompletionOptions) }
        def provider
          Interface::CompletionOptions.new(
            resolve_provider: false,
            trigger_characters: ["/"],
            completion_item: {
              labelDetailsSupport: true,
            },
          )
        end
      end

      ResponseType = type_member { { fixed: T::Array[Interface::CompletionItem] } }

      sig do
        params(
          document: Document,
          index: RubyIndexer::Index,
          position: T::Hash[Symbol, T.untyped],
          typechecker_enabled: T::Boolean,
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(document, index, position, typechecker_enabled, dispatcher)
        super()
        @target = T.let(nil, T.nilable(Prism::Node))
        @dispatcher = dispatcher
        # Completion always receives the position immediately after the character that was just typed. Here we adjust it
        # back by 1, so that we find the right node
        char_position = document.create_scanner.find_char_position(position) - 1
        matched, parent, nesting = document.locate(
          document.tree,
          char_position,
          node_types: [Prism::CallNode, Prism::ConstantReadNode, Prism::ConstantPathNode],
        )

        @listener = T.let(
          Listeners::Completion.new(index, nesting, typechecker_enabled, dispatcher),
          Listener[ResponseType],
        )

        return unless matched && parent

        @target = case matched
        when Prism::CallNode
          message = matched.message

          if message == "require"
            args = matched.arguments&.arguments
            return if args.nil? || args.is_a?(Prism::ForwardingArgumentsNode)

            argument = args.first
            return unless argument.is_a?(Prism::StringNode)
            return unless (argument.location.start_offset..argument.location.end_offset).cover?(char_position)

            argument
          else
            matched
          end
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          if parent.is_a?(Prism::ConstantPathNode) && matched.is_a?(Prism::ConstantReadNode)
            parent
          else
            matched
          end
        end
      end

      sig { override.returns(ResponseType) }
      def response
        return [] unless @target

        @dispatcher.dispatch_once(@target)
        @listener.response
      end
    end
  end
end
