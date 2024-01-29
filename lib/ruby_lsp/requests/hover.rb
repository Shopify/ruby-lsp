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
          index: RubyIndexer::Index,
          position: T::Hash[Symbol, T.untyped],
          dispatcher: Prism::Dispatcher,
          typechecker_enabled: T::Boolean,
        ).void
      end
      def initialize(document, index, position, dispatcher, typechecker_enabled)
        super()
        @target = T.let(nil, T.nilable(Prism::Node))
        @target, parent, nesting = document.locate_node(
          position,
          node_types: Listeners::Hover::ALLOWED_TARGETS,
        )

        if (Listeners::Hover::ALLOWED_TARGETS.include?(parent.class) &&
            !Listeners::Hover::ALLOWED_TARGETS.include?(@target.class)) ||
            (parent.is_a?(Prism::ConstantPathNode) && @target.is_a?(Prism::ConstantReadNode))
          @target = parent
        end

        @listeners = T.let([], T::Array[Listener[ResponseType]])

        # Don't need to instantiate any listeners if there's no target
        return unless @target

        uri = document.uri
        @listeners = T.let(
          [Listeners::Hover.new(uri, nesting, index, dispatcher, typechecker_enabled)],
          T::Array[Listener[ResponseType]],
        )
        Addon.addons.each do |addon|
          addon_listener = addon.create_hover_listener(nesting, index, dispatcher)
          @listeners << addon_listener if addon_listener
        end

        @dispatcher = dispatcher
      end

      sig { override.returns(ResponseType) }
      def perform
        return unless @target

        @dispatcher.dispatch_once(@target)
        responses = @listeners.map(&:response).compact

        first_response, *other_responses = responses

        return unless first_response

        # TODO: other_responses should never be nil. Check Sorbet
        T.must(other_responses).each do |other_response|
          first_response.contents.value << "\n\n" << other_response.contents.value
        end

        first_response
      end
    end
  end
end
