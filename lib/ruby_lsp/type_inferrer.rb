# typed: strict
# frozen_string_literal: true

module RubyLsp
  # A minimalistic type checker to try to resolve types that can be inferred without requiring a type system or
  # annotations
  class TypeInferrer
    extend T::Sig

    sig { params(index: RubyIndexer::Index).void }
    def initialize(index)
      @index = index
    end

    sig { params(node_context: NodeContext).returns(T.nilable(String)) }
    def infer_receiver_type(node_context)
      node = node_context.node

      case node
      when Prism::CallNode
        infer_receiver_for_call_node(node, node_context)
      when Prism::InstanceVariableReadNode, Prism::InstanceVariableAndWriteNode, Prism::InstanceVariableWriteNode,
        Prism::InstanceVariableOperatorWriteNode, Prism::InstanceVariableOrWriteNode, Prism::InstanceVariableTargetNode,
        Prism::SuperNode, Prism::ForwardingSuperNode
        self_receiver_handling(node_context)
      end
    end

    private

    sig { params(node: Prism::CallNode, node_context: NodeContext).returns(T.nilable(String)) }
    def infer_receiver_for_call_node(node, node_context)
      receiver = node.receiver

      case receiver
      when Prism::SelfNode, nil
        self_receiver_handling(node_context)
      when Prism::ConstantPathNode, Prism::ConstantReadNode
        # When the receiver is a constant reference, we have to try to resolve it to figure out the right
        # receiver. But since the invocation is directly on the constant, that's the singleton context of that
        # class/module
        receiver_name = constant_name(receiver)
        return unless receiver_name

        resolved_receiver = @index.resolve(receiver_name, node_context.nesting)
        name = resolved_receiver&.first&.name
        return unless name

        *parts, last = name.split("::")
        return "#{last}::<Class:#{last}>" if parts.empty?

        "#{parts.join("::")}::#{last}::<Class:#{last}>"
      end
    end

    sig { params(node_context: NodeContext).returns(String) }
    def self_receiver_handling(node_context)
      nesting = node_context.nesting
      # If we're at the top level, then the invocation is happening on `<main>`, which is a special singleton that
      # inherits from Object
      return "Object" if nesting.empty?
      return node_context.fully_qualified_name if node_context.surrounding_method

      # If we're not inside a method, then we're inside the body of a class or module, which is a singleton
      # context
      "#{nesting.join("::")}::<Class:#{nesting.last}>"
    end

    sig do
      params(
        node: T.any(
          Prism::ConstantPathNode,
          Prism::ConstantReadNode,
        ),
      ).returns(T.nilable(String))
    end
    def constant_name(node)
      node.full_name
    rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError,
           Prism::ConstantPathNode::MissingNodesInConstantPathError
      nil
    end
  end
end
