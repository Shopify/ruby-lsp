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

        sig { params(node: Prism::CallNode).returns(T::Boolean) }
        def match?(node)
          receiver_matches?(node) && arity_matches?(node)
        end

        private

        sig { params(node: Prism::CallNode).returns(T::Boolean) }
        def receiver_matches?(node)
          node_receiver = node.receiver
          (node_receiver && @receiver && node_receiver.location.slice == "T") || (!node_receiver && !@receiver)
        end

        sig { params(node: Prism::CallNode).returns(T::Boolean) }
        def arity_matches?(node)
          node_arity = node.arguments&.arguments&.size || 0

          case @arity
          when Integer
            node_arity == @arity
          when Range
            @arity.cover?(node_arity)
          end
        end
      end
    end
  end
end
