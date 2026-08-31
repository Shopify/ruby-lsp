# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # @abstract
    class Request
      include Support::Common

      class InvalidFormatter < StandardError; end

      # @abstract
      #: -> untyped
      def perform
        raise AbstractMethodInvokedError
      end

      private

      # Signals to the client that the request should be delegated to the language server server for the host language
      # in ERB files
      #: (GlobalState global_state, Document[untyped] document, Integer char_position) -> void
      def delegate_request_if_needed!(global_state, document, char_position)
        if global_state.client_capabilities.supports_request_delegation &&
            document.is_a?(ERBDocument) &&
            document.inside_host_language?(char_position)
          raise DelegateRequestError
        end
      end

      # Based on a constant node target, a constant path node parent and a position, this method will find the exact
      # portion of the constant path that matches the requested position, for higher precision in hover and
      # definition. For example:
      #
      # ```ruby
      # Foo::Bar::Baz
      #  #        ^ Going to definition here should go to Foo::Bar::Baz
      #  #   ^ Going to definition here should go to Foo::Bar
      # #^ Going to definition here should go to Foo
      # ```
      #: (Prism::Node target, Prism::Node parent, Hash[Symbol, Integer] position) -> Prism::Node
      def determine_target(target, parent, position)
        return target unless parent.is_a?(Prism::ConstantPathNode)

        target = parent #: Prism::Node
        parent = target #: as Prism::ConstantPathNode
          .parent #: Prism::Node?

        while parent && covers_position?(parent.location, position)
          target = parent
          parent = target.is_a?(Prism::ConstantPathNode) ? target.parent : nil
        end

        target
      end
    end
  end
end
