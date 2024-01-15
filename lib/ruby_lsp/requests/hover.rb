# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/hover"
require "ruby_lsp/response_builder"

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
          node_types: Listeners::Hover::ALLOWED_TARGETS,
        )

        if (Listeners::Hover::ALLOWED_TARGETS.include?(parent.class) &&
            !Listeners::Hover::ALLOWED_TARGETS.include?(target.class)) ||
            (parent.is_a?(Prism::ConstantPathNode) && target.is_a?(Prism::ConstantReadNode))
          target = parent
        end

        @listeners = T.let([], T::Array[Listener[HoverResponseBuilder]])

        # Don't need to instantiate any listeners if there's no target
        return unless target

        uri = document.uri
        @response_builder = T.let(HoverResponseBuilder.new, HoverResponseBuilder)
        Listeners::Hover.new(@response_builder, uri, nesting, index, dispatcher, typechecker_enabled)
        Addon.addons.each do |addon|
          addon.create_hover_listener(@response_builder, nesting, index, dispatcher)
        end

        @target = T.let(target, Prism::Node)
        @dispatcher = dispatcher
      end

      sig { override.returns(ResponseType) }
      def perform
        @dispatcher.dispatch_once(@target)

        return if @response_builder.empty?

        Interface::Hover.new(
          contents: Interface::MarkupContent.new(
            kind: "markdown",
            value: @response_builder.build_concatenated_response,
          ),
        )
      end
    end
  end
end
