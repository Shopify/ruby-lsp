# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    # @abstract
    class ResponseBuilder
      extend T::Generic

      # @abstract
      #: -> top
      def response; end
    end
  end
end
