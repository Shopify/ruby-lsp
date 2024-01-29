# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class ResponseBuilder
      extend T::Sig
      extend T::Generic

      abstract!

      ResponseType = type_member { { upper: Object } }

      sig { abstract.returns(ResponseType) }
      def response; end
    end
  end
end
