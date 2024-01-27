# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class Hover < ResponseBuilder
      ResponseType = type_member { { fixed: String } }

      extend T::Sig
      extend T::Generic

      sig { void }
      def initialize
        super
        @stack = T.let(
          [],
          T::Array[String],
        )
      end

      sig { params(hover_response: String).void }
      def push(hover_response)
        @stack << hover_response
      end

      alias_method(:<<, :push)

      sig { returns(T::Boolean) }
      def empty?
        @stack.empty?
      end

      sig { override.returns(String) }
      def response
        @stack.join("\n\n")
      end
    end
  end
end
