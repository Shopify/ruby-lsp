# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class Definition < ResponseBuilder
      ResponseType = type_member { { fixed: T::Array[Interface::Location] } }

      extend T::Sig

      sig { void }
      def initialize
        super
        @locations = T.let([], ResponseType)
      end

      sig { params(location: Interface::Location).void }
      def <<(location)
        @locations << location
      end

      sig { override.returns(ResponseType) }
      def response
        @locations
      end
    end
  end
end
