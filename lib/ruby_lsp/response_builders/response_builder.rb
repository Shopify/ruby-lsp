# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class ResponseBuilder
      extend T::Sig
      extend T::Generic

      abstract!

      sig { abstract.returns(T.anything) }
      def response; end
    end
  end
end
