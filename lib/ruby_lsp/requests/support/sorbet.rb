# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class Sorbet
        class << self
          extend T::Sig

          ANNOTATIONS = T.let(
            {
              "abstract!" => Annotation.new(arity: 0),
              "absurd" => Annotation.new(arity: 1, receiver: true),
              "all" => Annotation.new(arity: (2..), receiver: true),
              "any" => Annotation.new(arity: (2..), receiver: true),
              "assert_type!" => Annotation.new(arity: 2, receiver: true),
              "attached_class" => Annotation.new(arity: 0, receiver: true),
              "bind" => Annotation.new(arity: 2, receiver: true),
              "cast" => Annotation.new(arity: 2, receiver: true),
              "class_of" => Annotation.new(arity: 1, receiver: true),
              "enums" => Annotation.new(arity: 0),
              "interface!" => Annotation.new(arity: 0),
              "let" => Annotation.new(arity: 2, receiver: true),
              "mixes_in_class_methods" => Annotation.new(arity: 1),
              "must" => Annotation.new(arity: 1, receiver: true),
              "must_because" => Annotation.new(arity: 1, receiver: true),
              "nilable" => Annotation.new(arity: 1, receiver: true),
              "noreturn" => Annotation.new(arity: 0, receiver: true),
              "requires_ancestor" => Annotation.new(arity: 0),
              "reveal_type" => Annotation.new(arity: 1, receiver: true),
              "sealed!" => Annotation.new(arity: 0),
              "self_type" => Annotation.new(arity: 0, receiver: true),
              "sig" => Annotation.new(arity: 0),
              "type_member" => Annotation.new(arity: (0..1)),
              "type_template" => Annotation.new(arity: 0),
              "unsafe" => Annotation.new(arity: 1),
              "untyped" => Annotation.new(arity: 0, receiver: true),
            },
            T::Hash[String, Annotation],
          )

          sig do
            params(
              node: YARP::CallNode,
            ).returns(T::Boolean)
          end
          def annotation?(node)
            annotation = ANNOTATIONS[node.name]

            return false unless annotation

            return false unless receiver_matches?(node.receiver, annotation)

            arity = node.arguments&.arguments&.size || 0

            arity_matches?(arity, annotation.arity)
          end

          private

          sig { params(receiver: T.nilable(YARP::Node), annotation: Annotation).returns(T::Boolean) }
          def receiver_matches?(receiver, annotation)
            (receiver && annotation.receiver && receiver.location.slice == "T") ||
              (!receiver && !annotation.receiver)
          end

          sig { params(arity: Integer, annotation_arity: T.any(Integer, T::Range[Integer])).returns(T::Boolean) }
          def arity_matches?(arity, annotation_arity)
            case annotation_arity
            when Integer
              arity == annotation_arity
            when Range
              annotation_arity.cover?(arity)
            end
          end
        end
      end
    end
  end
end
