# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # :nodoc:
    class Request
      extend T::Sig
      extend T::Generic

      abstract!

      sig { abstract.returns(T.anything) }
      def perform; end

      private

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
    end
  end
end
