# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/hover"

module RubyLsp
  module Requests
    # ![Hover demo](../../hover.gif)
    #
    # The [hover request](https://microsoft.github.io/language-server-protocol/specification#textDocument_hover)
    # displays the documentation for the symbol currently under the cursor.
    #
    # # Example
    #
    # ```ruby
    # String # -> Hovering over the class reference will show all declaration locations and the documentation
    # ```
    class Hover < Request
      extend T::Sig
      extend T::Generic

      class << self
        extend T::Sig

        sig { returns(Interface::HoverClientCapabilities) }
        def provider
          Interface::HoverClientCapabilities.new(dynamic_registration: false)
        end
      end

      ResponseType = type_member { { fixed: T.nilable(Interface::Hover) } }

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
        node_context = document.locate_node(position, node_types: Listeners::Hover::ALLOWED_TARGETS)
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
        Listeners::Hover.new(@response_builder, global_state, uri, node_context, dispatcher, typechecker_enabled)
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
