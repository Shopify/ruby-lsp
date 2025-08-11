# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/signature_help"

module RubyLsp
  module Requests
    # The [signature help
    # request](https://microsoft.github.io/language-server-protocol/specification#textDocument_signatureHelp) displays
    # information about the parameters of a method as you type an invocation.
    class SignatureHelp < Request
      class << self
        #: -> Interface::SignatureHelpOptions
        def provider
          # Identifier characters are automatically included, such as A-Z, a-z, 0-9, _, * or :
          Interface::SignatureHelpOptions.new(
            trigger_characters: ["(", " ", ","],
          )
        end
      end

      #: ((RubyDocument | ERBDocument) document, GlobalState global_state, Hash[Symbol, untyped] position, Hash[Symbol, untyped]? context, Prism::Dispatcher dispatcher, SorbetLevel sorbet_level) -> void
      def initialize(document, global_state, position, context, dispatcher, sorbet_level) # rubocop:disable Metrics/ParameterLists
        super()

        char_position, _ = document.find_index_by_position(position)
        delegate_request_if_needed!(global_state, document, char_position)

        node_context = RubyDocument.locate(
          document.ast,
          char_position,
          node_types: [Prism::CallNode],
          code_units_cache: document.code_units_cache,
        )

        target = adjust_for_nested_target(node_context.node, node_context.parent, position)

        @target = target #: Prism::Node?
        @dispatcher = dispatcher
        @response_builder = ResponseBuilders::SignatureHelp.new #: ResponseBuilders::SignatureHelp
        Listeners::SignatureHelp.new(@response_builder, global_state, node_context, dispatcher, sorbet_level)
      end

      # @override
      #: -> Interface::SignatureHelp?
      def perform
        return unless @target

        @dispatcher.dispatch_once(@target)
        @response_builder.response
      end

      private

      # Adjust the target of signature help in the case where we have nested method calls. This is necessary so that we
      # select the right target in a situation like this:
      #
      # foo(another_method_call)
      #
      # In that case, we want to provide signature help for `foo` and not `another_method_call`.
      #: (Prism::Node? target, Prism::Node? parent, Hash[Symbol, untyped] position) -> Prism::Node?
      def adjust_for_nested_target(target, parent, position)
        # If the parent node is not a method call, then make no adjustments
        return target unless parent.is_a?(Prism::CallNode)
        # If the parent is a method call, but the target isn't, then return the parent
        return parent unless target.is_a?(Prism::CallNode)

        # If both are method calls, we check the arguments of the inner method call. If there are no arguments, then
        # we're providing signature help for the outer method call.
        #
        # If there are arguments, then we check if the arguments node covers the requested position. If it doesn't
        # cover, then we're providing signature help for the outer method call.
        arguments = target.arguments
        arguments.nil? || !node_covers?(arguments, position) ? parent : target
      end

      #: (Prism::Node node, Hash[Symbol, untyped] position) -> bool
      def node_covers?(node, position)
        location = node.location
        start_line = location.start_line - 1
        start_character = location.start_column
        end_line = location.end_line - 1
        end_character = location.end_column

        start_covered = start_line < position[:line] ||
          (start_line == position[:line] && start_character <= position[:character])

        end_covered = end_line > position[:line] ||
          (end_line == position[:line] && end_character >= position[:character])

        start_covered && end_covered
      end
    end
  end
end
