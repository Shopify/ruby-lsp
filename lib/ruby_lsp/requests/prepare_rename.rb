# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The
    # [prepare_rename](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_prepareRename)
    # request checks the validity of a rename operation at a given location.
    class PrepareRename < Request
      extend T::Sig
      include Support::Common

      sig do
        params(
          document: T.any(RubyDocument, ERBDocument),
          position: T::Hash[Symbol, T.untyped],
        ).void
      end
      def initialize(document, position)
        super()
        @document = document
        @position = T.let(position, T::Hash[Symbol, Integer])
      end

      sig { override.returns(T.nilable(Interface::Range)) }
      def perform
        char_position = @document.create_scanner.find_char_position(@position)

        node_context = RubyDocument.locate(
          @document.parse_result.value,
          char_position,
          node_types: [Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::ConstantPathTargetNode],
          code_units_cache: @document.code_units_cache,
        )
        target = node_context.node
        parent = node_context.parent
        return if !target || target.is_a?(Prism::ProgramNode)

        if target.is_a?(Prism::ConstantReadNode) && parent.is_a?(Prism::ConstantPathNode)
          target = determine_target(
            target,
            parent,
            @position,
          )
        end

        target = T.cast(target, T.any(Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::ConstantPathTargetNode))
        range_from_location(target.location)
      end
    end
  end
end
