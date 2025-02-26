# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The
    # [prepare_rename](https://microsoft.github.io/language-server-protocol/specification#textDocument_prepareRename)
    # # request checks the validity of a rename operation at a given location.
    class PrepareRename < Request
      include Support::Common

      #: (RubyDocument document, Hash[Symbol, untyped] position) -> void
      def initialize(document, position)
        super()
        @document = document
        @position = position #: Hash[Symbol, Integer]
      end

      # @override
      #: -> Interface::Range?
      def perform
        char_position, _ = @document.find_index_by_position(@position)

        node_context = RubyDocument.locate(
          @document.ast,
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

        range_from_location(target.location)
      end
    end
  end
end
