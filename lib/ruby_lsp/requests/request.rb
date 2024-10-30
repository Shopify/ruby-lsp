# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    class Request
      extend T::Sig
      extend T::Generic

      class InvalidFormatter < StandardError; end

      abstract!

      sig { abstract.returns(T.anything) }
      def perform; end

      private

      # Signals to the client that the request should be delegated to the language server server for the host language
      # in ERB files
      sig do
        params(
          global_state: GlobalState,
          document: Document[T.untyped],
          char_position: Integer,
        ).void
      end
      def delegate_request_if_needed!(global_state, document, char_position)
        if global_state.client_capabilities.supports_request_delegation &&
            document.is_a?(ERBDocument) &&
            document.inside_host_language?(char_position)
          raise DelegateRequestError
        end
      end

      # Checks if a location covers a position
      sig { params(location: Prism::Location, position: T.untyped).returns(T::Boolean) }
      def cover?(location, position)
        start_covered =
          location.start_line - 1 < position[:line] ||
          (
            location.start_line - 1 == position[:line] &&
              location.start_column <= position[:character]
          )
        end_covered =
          location.end_line - 1 > position[:line] ||
          (
            location.end_line - 1 == position[:line] &&
              location.end_column >= position[:character]
          )
        start_covered && end_covered
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
      sig do
        params(
          target: Prism::Node,
          parent: Prism::Node,
          position: T::Hash[Symbol, Integer],
        ).returns(Prism::Node)
      end
      def determine_target(target, parent, position)
        return target unless parent.is_a?(Prism::ConstantPathNode)

        target = T.let(parent, Prism::Node)
        parent = T.let(T.cast(target, Prism::ConstantPathNode).parent, T.nilable(Prism::Node))

        while parent && cover?(parent.location, position)
          target = parent
          parent = target.is_a?(Prism::ConstantPathNode) ? target.parent : nil
        end

        target
      end

      # Checks if a given location covers the position requested
      sig { params(location: T.nilable(Prism::Location), position: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
      def covers_position?(location, position)
        return false unless location

        start_line = location.start_line - 1
        end_line = location.end_line - 1
        line = position[:line]
        character = position[:character]

        (start_line < line || (start_line == line && location.start_column <= character)) &&
          (end_line > line || (end_line == line && location.end_column >= character))
      end
    end
  end
end
