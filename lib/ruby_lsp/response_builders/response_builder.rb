# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class ResponseBuilder
      extend T::Generic
      extend T::Sig

      abstract!

      sig { abstract.returns(T.anything) }
      def response; end
    end
  end
end
