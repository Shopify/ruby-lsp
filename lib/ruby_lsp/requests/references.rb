# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The
    # [references](https://microsoft.github.io/language-server-protocol/specification#textDocument_references)
    # request finds all references for the selected symbol.
    class References < Request
      extend T::Sig
      include Support::Common

      sig do
        params(
          global_state: GlobalState,
          store: Store,
          document: T.any(RubyDocument, ERBDocument),
          params: T::Hash[Symbol, T.untyped],
        ).void
      end
      def initialize(global_state, store, document, params)
        super()
        @global_state = global_state
        @store = store
        @document = document
        @params = params
        @locations = T.let([], T::Array[Interface::Location])
      end

      sig { override.returns(T::Array[Interface::Location]) }
      def perform
        position = @params[:position]
        char_position = @document.create_scanner.find_char_position(position)

        node_context = RubyDocument.locate(
          @document.parse_result.value,
          char_position,
          node_types: [Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::ConstantPathTargetNode],
          encoding: @global_state.encoding,
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
          T.any(Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::ConstantPathTargetNode),
        )

        name = constant_name(target)
        return @locations unless name

        entries = @global_state.index.resolve(name, node_context.nesting)
        return @locations unless entries

        fully_qualified_name = T.must(entries.first).name

        Dir.glob(File.join(@global_state.workspace_path, "**/*.rb")).each do |path|
          uri = URI::Generic.from_path(path: path)
          # If the document is being managed by the client, then we should use whatever is present in the store instead
          # of reading from disk
          next if @store.key?(uri)

          parse_result = Prism.parse_file(path)
          collect_references(fully_qualified_name, parse_result, uri)
        end

        @store.each do |_uri, document|
          collect_references(fully_qualified_name, document.parse_result, document.uri)
        end

        @locations
      end

      private

      sig do
        params(
          fully_qualified_name: String,
          parse_result: Prism::ParseResult,
          uri: URI::Generic,
        ).void
      end
      def collect_references(fully_qualified_name, parse_result, uri)
        dispatcher = Prism::Dispatcher.new
        finder = RubyIndexer::ReferenceFinder.new(
          fully_qualified_name,
          @global_state.index,
          dispatcher,
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
