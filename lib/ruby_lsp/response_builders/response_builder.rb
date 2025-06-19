# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    # @abstract
    class ResponseBuilder
      # @abstract
      #: -> top
      def response
        raise AbstractMethodInvokedError
      end
    end
  end
end
