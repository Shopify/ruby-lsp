# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class FoldingRanges < ResponseBuilder
      ResponseType = type_member { { fixed: T::Array[Interface::FoldingRange] } }

      extend T::Sig

      sig { void }
      def initialize
        super
        @folding_ranges = T.let([], ResponseType)
      end

      sig { params(folding_range: Interface::FoldingRange).void }
      def <<(folding_range)
        @folding_ranges << folding_range
      end

      sig { override.returns(ResponseType) }
      def response
        @folding_ranges
      end
    end
  end
end
