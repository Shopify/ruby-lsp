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
              "abstract!" => { arity: 0 },
              "absurd" => { arity: 1, receiver: true },
              "all" => { arity: (2..), receiver: true },
              "any" => { arity: (2..), receiver: true },
              "assert_type!" => { arity: 2, receiver: true },
              "attached_class" => { arity: 0, receiver: true },
              "bind" => { arity: 2, receiver: true },
              "cast" => { arity: 2, receiver: true },
              "class_of" => { arity: 1, receiver: true },
              "enums" => { arity: 0, receiver: false },
              "interface!" => { arity: 0, receiver: false },
              "let" => { arity: 2, receiver: true },
              "mixes_in_class_methods" => { arity: 1, receiver: false },
              "must" => { arity: 1, receiver: true },
              "must_because" => { arity: 1, receiver: true },
              "nilable" => { arity: 1, receiver: true },
              "noreturn" => { arity: 0, receiver: true },
              "requires_ancestor" => { arity: 0, receiver: false },
              "reveal_type" => { arity: 1, receiver: true },
              "sealed!" => { arity: 0, receiver: false },
              "self_type" => { arity: 0, receiver: true },
              "sig" => { arity: 0, receiver: false },
              "type_member" => { arity: (0..1), receiver: false },
              "type_template" => { arity: 0, receiver: false },
              "unsafe" => { arity: 1, receiver: false },
              "untyped" => { arity: 0, receiver: true },
            },
            T::Hash[String, { arity: T.any(Integer, T::Range[Integer]), receiver: T::Boolean }],
          )

          sig do
            params(
              node: YARP::CallNode,
            ).returns(T::Boolean)
          end
          def annotation?(node)
            annotation = ANNOTATIONS[node.name]

            return false if annotation.nil?

            receiver = node.receiver

            unless (receiver && annotation[:receiver] && receiver.location.slice == "T") ||
                (!receiver && !annotation[:receiver])
              return false
            end

            arity = node.arguments&.arguments&.size || 0
            annotation_arity = annotation[:arity]

            case annotation_arity
            when Integer
              arity == annotation_arity
            when Range
              annotation_arity.cover?(arity)
            else
              false
            end
          end
        end
      end
    end
  end
end
