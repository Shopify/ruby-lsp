# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [workspace symbol](https://microsoft.github.io/language-server-protocol/specification#workspace_symbol)
    # request allows fuzzy searching declarations in the entire project. On VS Code, use CTRL/CMD + T to search for
    # symbols.
    class WorkspaceSymbol < Request
      include Support::Common

      #: (GlobalState global_state, String? query) -> void
      def initialize(global_state, query)
        super()
        @query = query
        @graph = global_state.graph #: Rubydex::Graph
      end

      # @override
      #: -> Array[Interface::WorkspaceSymbol]
      def perform
        response = []

        @graph.fuzzy_search(@query || "").each do |declaration|
          name = declaration.name

          declaration.definitions.each do |definition|
            location = definition.location
            uri = URI(location.uri)
            file_path = uri.full_path

            # We only show symbols declared in the workspace
            in_dependencies = file_path && !not_in_dependencies?(file_path)
            next if in_dependencies

            response << definition.to_lsp_workspace_symbol(name)
          end
        end

        response
      end
    end
  end
end
