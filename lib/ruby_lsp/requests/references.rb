# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The
    # [references](https://microsoft.github.io/language-server-protocol/specification#textDocument_references)
    # request finds all references for the selected symbol.
    class References < Request
      include Support::Common

      #: (GlobalState global_state, Store store, (RubyDocument | ERBDocument) document, Hash[Symbol, untyped] params) -> void
      def initialize(global_state, store, document, params)
        super()
        @global_state = global_state
        @store = store
        @document = document
        @params = params
        @locations = [] #: Array[Interface::Location]
      end

      # @override
      #: -> Array[Interface::Location]
      def perform
        position = @params[:position]
        char_position, _ = @document.find_index_by_position(position)

        node_context = RubyDocument.locate(
          @document.parse_result.value,
          char_position,
          node_types: [
            Prism::ConstantReadNode,
            Prism::ConstantPathNode,
            Prism::ConstantPathTargetNode,
            Prism::InstanceVariableAndWriteNode,
            Prism::InstanceVariableOperatorWriteNode,
            Prism::InstanceVariableOrWriteNode,
            Prism::InstanceVariableReadNode,
            Prism::InstanceVariableTargetNode,
            Prism::InstanceVariableWriteNode,
            Prism::CallNode,
            Prism::DefNode,
          ],
          code_units_cache: @document.code_units_cache,
        )
        target = node_context.node
        parent = node_context.parent
        return @locations if !target || target.is_a?(Prism::ProgramNode)

        if target.is_a?(Prism::ConstantReadNode) && parent.is_a?(Prism::ConstantPathNode)
          target = determine_target(
            target,
            parent,
            position,
          )
        end

        target = T.cast(
          target,
          T.any(
            Prism::ConstantReadNode,
            Prism::ConstantPathNode,
            Prism::ConstantPathTargetNode,
            Prism::InstanceVariableAndWriteNode,
            Prism::InstanceVariableOperatorWriteNode,
            Prism::InstanceVariableOrWriteNode,
            Prism::InstanceVariableReadNode,
            Prism::InstanceVariableTargetNode,
            Prism::InstanceVariableWriteNode,
            Prism::CallNode,
            Prism::DefNode,
          ),
        )

        reference_target = create_reference_target(target, node_context)
        return @locations unless reference_target

        Dir.glob(File.join(@global_state.workspace_path, "**/*.rb")).each do |path|
          uri = URI::Generic.from_path(path: path)
          # If the document is being managed by the client, then we should use whatever is present in the store instead
          # of reading from disk
          next if @store.key?(uri)

          parse_result = Prism.parse_file(path)
          collect_references(reference_target, parse_result, uri)
        rescue Errno::EISDIR, Errno::ENOENT
          # If `path` is a directory, just ignore it and continue. If the file doesn't exist, then we also ignore it.
        end

        @store.each do |_uri, document|
          collect_references(reference_target, document.parse_result, document.uri)
        end

        @locations
      end

      private

      #: ((Prism::ConstantReadNode | Prism::ConstantPathNode | Prism::ConstantPathTargetNode | Prism::InstanceVariableAndWriteNode | Prism::InstanceVariableOperatorWriteNode | Prism::InstanceVariableOrWriteNode | Prism::InstanceVariableReadNode | Prism::InstanceVariableTargetNode | Prism::InstanceVariableWriteNode | Prism::CallNode | Prism::DefNode) target_node, NodeContext node_context) -> RubyIndexer::ReferenceFinder::Target?
      def create_reference_target(target_node, node_context)
        case target_node
        when Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::ConstantPathTargetNode
          name = RubyIndexer::Index.constant_name(target_node)
          return unless name

          entries = @global_state.index.resolve(name, node_context.nesting)
          return unless entries

          fully_qualified_name = entries.first #: as !nil
            .name
          RubyIndexer::ReferenceFinder::ConstTarget.new(fully_qualified_name)
        when
          Prism::InstanceVariableAndWriteNode,
          Prism::InstanceVariableOperatorWriteNode,
          Prism::InstanceVariableOrWriteNode,
          Prism::InstanceVariableReadNode,
          Prism::InstanceVariableTargetNode,
          Prism::InstanceVariableWriteNode
          RubyIndexer::ReferenceFinder::InstanceVariableTarget.new(target_node.name.to_s)
        when Prism::CallNode, Prism::DefNode
          RubyIndexer::ReferenceFinder::MethodTarget.new(target_node.name.to_s)
        end
      end

      #: (RubyIndexer::ReferenceFinder::Target target, Prism::ParseResult parse_result, URI::Generic uri) -> void
      def collect_references(target, parse_result, uri)
        dispatcher = Prism::Dispatcher.new
        finder = RubyIndexer::ReferenceFinder.new(
          target,
          @global_state.index,
          dispatcher,
          uri,
          include_declarations: @params.dig(:context, :includeDeclaration) || true,
        )
        dispatcher.visit(parse_result.value)

        finder.references.each do |reference|
          @locations << Interface::Location.new(
            uri: uri.to_s,
            range: range_from_location(reference.location),
          )
        end
      end
    end
  end
end
