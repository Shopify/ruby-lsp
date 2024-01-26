# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class CodeLens < ResponseBuilder
      ResponseType = type_member { { fixed: T::Array[Interface::CodeLens] } }

      extend T::Sig

      sig { void }
      def initialize
        super
        @stack = T.let([], ResponseType)
      end

      sig { params(code_lens: Interface::CodeLens).void }
      def <<(*code_lens)
        @stack.concat(code_lens)
      end

      sig { override.returns(ResponseType) }
      def response
        @stack
      end
    end
  end
end
