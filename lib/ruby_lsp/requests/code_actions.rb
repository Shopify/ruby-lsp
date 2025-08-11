# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [code actions](https://microsoft.github.io/language-server-protocol/specification#textDocument_codeAction)
    # request informs the editor of RuboCop quick fixes that can be applied. These are accessible by hovering over a
    # specific diagnostic.
    class CodeActions < Request
      EXTRACT_TO_VARIABLE_TITLE = "Refactor: Extract Variable"
      EXTRACT_TO_METHOD_TITLE = "Refactor: Extract Method"
      TOGGLE_BLOCK_STYLE_TITLE = "Refactor: Toggle block style"
      CREATE_ATTRIBUTE_READER = "Create Attribute Reader"
      CREATE_ATTRIBUTE_WRITER = "Create Attribute Writer"
      CREATE_ATTRIBUTE_ACCESSOR = "Create Attribute Accessor"

      INSTANCE_VARIABLE_NODES = [
        Prism::InstanceVariableAndWriteNode,
        Prism::InstanceVariableOperatorWriteNode,
        Prism::InstanceVariableOrWriteNode,
        Prism::InstanceVariableReadNode,
        Prism::InstanceVariableTargetNode,
        Prism::InstanceVariableWriteNode,
      ] #: Array[singleton(Prism::Node)]

      class << self
        #: -> Interface::CodeActionRegistrationOptions
        def provider
          Interface::CodeActionRegistrationOptions.new(
            document_selector: nil,
            resolve_provider: true,
          )
        end
      end

      #: ((RubyDocument | ERBDocument) document, Hash[Symbol, untyped] range, Hash[Symbol, untyped] context) -> void
      def initialize(document, range, context)
        super()
        @document = document
        @uri = document.uri #: URI::Generic
        @range = range
        @context = context
      end

      # @override
      #: -> (Array[Interface::CodeAction] & Object)?
      def perform
        diagnostics = @context[:diagnostics]

        code_actions = diagnostics.flat_map do |diagnostic|
          diagnostic.dig(:data, :code_actions) || []
        end

        # Only add refactor actions if there's a non empty selection in the editor
        unless @range.dig(:start) == @range.dig(:end)
          code_actions << Interface::CodeAction.new(
            title: EXTRACT_TO_VARIABLE_TITLE,
            kind: Constant::CodeActionKind::REFACTOR_EXTRACT,
            data: { range: @range, uri: @uri.to_s },
          )
          code_actions << Interface::CodeAction.new(
            title: EXTRACT_TO_METHOD_TITLE,
            kind: Constant::CodeActionKind::REFACTOR_EXTRACT,
            data: { range: @range, uri: @uri.to_s },
          )
          code_actions << Interface::CodeAction.new(
            title: TOGGLE_BLOCK_STYLE_TITLE,
            kind: Constant::CodeActionKind::REFACTOR_REWRITE,
            data: { range: @range, uri: @uri.to_s },
          )
        end
        code_actions.concat(attribute_actions)

        code_actions
      end

      private

      #: -> Array[Interface::CodeAction]
      def attribute_actions
        return [] unless @document.is_a?(RubyDocument)

        node = if @range.dig(:start) != @range.dig(:end)
          @document.locate_first_within_range(
            @range,
            node_types: INSTANCE_VARIABLE_NODES,
          )
        end

        if node.nil?
          node_context = @document.locate_node(
            @range[:start],
            node_types: CodeActions::INSTANCE_VARIABLE_NODES,
          )
          return [] unless INSTANCE_VARIABLE_NODES.include?(node_context.node.class)
        end

        [
          Interface::CodeAction.new(
            title: CREATE_ATTRIBUTE_READER,
            kind: Constant::CodeActionKind::EMPTY,
            data: { range: @range, uri: @uri.to_s },
          ),
          Interface::CodeAction.new(
            title: CREATE_ATTRIBUTE_WRITER,
            kind: Constant::CodeActionKind::EMPTY,
            data: { range: @range, uri: @uri.to_s },
          ),
          Interface::CodeAction.new(
            title: CREATE_ATTRIBUTE_ACCESSOR,
            kind: Constant::CodeActionKind::EMPTY,
            data: { range: @range, uri: @uri.to_s },
          ),
        ]
      end
    end
  end
end
