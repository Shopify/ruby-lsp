# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class Annotation
        extend T::Sig
        sig do
          params(
            arity: T.any(Integer, T::Range[Integer]),
            receiver: T::Boolean,
          ).void
        end
        def initialize(arity:, receiver: false)
          @arity = arity
          @receiver = receiver
        end

        sig { returns(T.any(Integer, T::Range[Integer])) }
        attr_reader :arity

        sig { returns(T::Boolean) }
        attr_reader :receiver
      end
    end
  end
end
