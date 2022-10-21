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

        sig { params(arity: T.any(T::Range[Integer], Integer)).returns(T::Boolean) }
        def supports_arity?(arity)
          if @arity.is_a?(Integer)
            @arity == arity
          elsif @arity.is_a?(Range)
            @arity.cover?(arity)
          else
            T.absurd(@arity)
          end
        end

        sig { params(receiver: T.nilable(String)).returns(T::Boolean) }
        def supports_receiver?(receiver)
          return receiver.nil? || receiver.empty? if @receiver == false

          receiver == "T"
        end
      end
    end
  end
end
