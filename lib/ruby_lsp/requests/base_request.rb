# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # :nodoc:
    class BaseRequest < Prism::Visitor
      extend T::Sig
      extend T::Helpers
      include Support::Common

      abstract!

      sig { params(document: Document).void }
      def initialize(document)
        @document = document
        super()
      end

      sig { abstract.returns(Object) }
      def run; end
    end
  end
end
