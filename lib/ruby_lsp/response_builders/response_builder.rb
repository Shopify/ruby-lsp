# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class ResponseBuilder
      extend T::Generic
      extend T::Sig

      abstract!

      # @abstract: def response: -> top
    end
  end
end
