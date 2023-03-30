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
              node: T.any(SyntaxTree::CallNode, SyntaxTree::VCall),
            ).returns(T::Boolean)
          end
          def annotation?(node)
            annotation = annotation(node)

            return false if annotation.nil?

            return false unless annotation.supports_receiver?(receiver_name(node))

            annotation.supports_arity?(node.arity)
          end

          private

          sig { params(node: T.any(SyntaxTree::CallNode, SyntaxTree::VCall)).returns(T.nilable(Annotation)) }
          def annotation(node)
            case node
            when SyntaxTree::VCall
              ANNOTATIONS[node.value.value]
            when SyntaxTree::CallNode
              message = node.message
              ANNOTATIONS[message.value] unless message.is_a?(Symbol)
            else
              T.absurd(node)
            end
          end

          sig do
            params(receiver: T.any(SyntaxTree::CallNode, SyntaxTree::VCall)).returns(T.nilable(String))
          end
          def receiver_name(receiver)
            case receiver
            when SyntaxTree::CallNode
              node_name(receiver.receiver)
            when SyntaxTree::VCall
              nil
            else
              T.absurd(receiver)
            end
          end

          sig do
            params(node: T.nilable(SyntaxTree::Node)).returns(T.nilable(String))
          end
          def node_name(node)
            case node
            when SyntaxTree::VarRef
              node.value.value
            when SyntaxTree::CallNode
              node_name(node.receiver)
            when SyntaxTree::VCall
              node_name(node.value)
            when SyntaxTree::Ident, SyntaxTree::Backtick, SyntaxTree::Const, SyntaxTree::Op
              node.value
            when NilClass, SyntaxTree::Node
              nil
            else
              T.absurd(node)
            end
          end
        end
      end
    end
  end
end
