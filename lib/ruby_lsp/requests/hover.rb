# typed: strict
# frozen_string_literal: true

require "ruby_lsp/listeners/hover"

module RubyLsp
  module Requests
    # The [hover request](https://microsoft.github.io/language-server-protocol/specification#textDocument_hover)
    # displays the documentation for the symbol currently under the cursor.
    #: [ResponseType = Interface::Hover?]
    class Hover < Request
      class << self
        #: -> Interface::HoverOptions
        def provider
          Interface::HoverOptions.new
        end
      end

      #: ((RubyDocument | ERBDocument) document, GlobalState global_state, Hash[Symbol, untyped] position, Prism::Dispatcher dispatcher, SorbetLevel sorbet_level) -> void
      def initialize(document, global_state, position, dispatcher, sorbet_level)
        super()

        char_position, _ = document.find_index_by_position(position)
        delegate_request_if_needed!(global_state, document, char_position)

        node_context = RubyDocument.locate(
          document.ast,
          char_position,
          node_types: Listeners::Hover::ALLOWED_TARGETS,
          code_units_cache: document.code_units_cache,
        )
        target = node_context.node
        parent = node_context.parent

        if should_refine_target?(parent, target)
          target = determine_target(
            target, #: as !nil
            parent, #: as !nil
            position,
          )
        elsif position_outside_target?(position, target)
          target = nil
        end

        # Don't need to instantiate any listeners if there's no target
        return unless target

        @target = target #: Prism::Node?
        uri = document.uri
        @response_builder = ResponseBuilders::Hover.new #: ResponseBuilders::Hover
        Listeners::Hover.new(@response_builder, global_state, uri, node_context, dispatcher, sorbet_level)
        Addon.addons.each do |addon|
          addon.create_hover_listener(@response_builder, node_context, dispatcher)
        end

        @dispatcher = dispatcher
      end

      # @override
      #: -> ResponseType
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

      private

      #: (Prism::Node? parent, Prism::Node? target) -> bool
      def should_refine_target?(parent, target)
        (Listeners::Hover::ALLOWED_TARGETS.include?(parent.class) &&
        !Listeners::Hover::ALLOWED_TARGETS.include?(target.class)) ||
          (parent.is_a?(Prism::ConstantPathNode) && target.is_a?(Prism::ConstantReadNode))
      end

      #: (Hash[Symbol, untyped] position, Prism::Node? target) -> bool
      def position_outside_target?(position, target)
        case target
        when Prism::GlobalVariableAndWriteNode,
          Prism::GlobalVariableOperatorWriteNode,
          Prism::GlobalVariableOrWriteNode,
          Prism::GlobalVariableWriteNode
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
