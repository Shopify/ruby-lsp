# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/hover"

module RubyLsp
  module Requests
    # The [hover request](https://microsoft.github.io/language-server-protocol/specification#textDocument_hover)
    # displays the documentation for the symbol currently under the cursor.
    class Hover < Request
      extend T::Sig
      extend T::Generic

      class << self
        extend T::Sig

        sig { returns(Interface::HoverOptions) }
        def provider
          Interface::HoverOptions.new
        end
      end

      ResponseType = type_member { { fixed: T.nilable(Interface::Hover) } }

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

        char_position = document.create_scanner.find_char_position(position)
        delegate_request_if_needed!(global_state, document, char_position)

        node_context = RubyDocument.locate(
          document.parse_result.value,
          char_position,
          node_types: Listeners::Hover::ALLOWED_TARGETS,
          encoding: global_state.encoding,
        )
        target = node_context.node
        parent = node_context.parent

        if (Listeners::Hover::ALLOWED_TARGETS.include?(parent.class) &&
            !Listeners::Hover::ALLOWED_TARGETS.include?(target.class)) ||
            (parent.is_a?(Prism::ConstantPathNode) && target.is_a?(Prism::ConstantReadNode))
          target = determine_target(
            T.must(target),
            T.must(parent),
            position,
          )
        elsif target.is_a?(Prism::CallNode) && target.name != :require && target.name != :require_relative &&
            !covers_position?(target.message_loc, position)

          target = nil
        end

        # Don't need to instantiate any listeners if there's no target
        return unless target

        @target = T.let(target, T.nilable(Prism::Node))
        uri = document.uri
        @response_builder = T.let(ResponseBuilders::Hover.new, ResponseBuilders::Hover)
        Listeners::Hover.new(@response_builder, global_state, uri, node_context, dispatcher, sorbet_level)
        Addon.addons.each do |addon|
          addon.create_hover_listener(@response_builder, node_context, dispatcher)
        end

        @dispatcher = dispatcher
      end

      sig { override.returns(ResponseType) }
      def perform
        return unless @target

        @dispatcher.dispatch_once(@target)

        return if @response_builder.empty?

        Interface::Hover.new(
          contents: Interface::MarkupContent.new(
            kind: "markdown",
            value: @response_builder.response,
          ),
        )
      end
    end
  end
end
