# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [workspace symbol](https://microsoft.github.io/language-server-protocol/specification#workspace_symbol)
    # request allows fuzzy searching declarations in the entire project. On VS Code, use CTRL/CMD + T to search for
    # symbols.
    class WorkspaceSymbol < Request
      extend T::Sig
      include Support::Common

      sig { params(global_state: GlobalState, query: T.nilable(String)).void }
      def initialize(global_state, query)
        super()
        @global_state = global_state
        @query = query
        @index = T.let(global_state.index, RubyIndexer::Index)
      end

      sig { override.returns(T::Array[Interface::WorkspaceSymbol]) }
      def perform
        @index.fuzzy_search(@query).filter_map do |entry|
          uri = entry.uri
          file_path = uri.full_path

          # We only show symbols declared in the workspace
          in_dependencies = file_path && !not_in_dependencies?(file_path)
          next if in_dependencies

          # We should never show private symbols when searching the entire workspace
          next if entry.private?

          kind = kind_for_entry(entry)
          loc = entry.location

          # We use the namespace as the container name, but we also use the full name as the regular name. The reason we
          # do this is to allow people to search for fully qualified names (e.g.: `Foo::Bar`). If we only included the
          # short name `Bar`, then searching for `Foo::Bar` would not return any results
          *container, _short_name = entry.name.split("::")

          Interface::WorkspaceSymbol.new(
            name: entry.name,
            container_name: container.join("::"),
            kind: kind,
            location: Interface::Location.new(
              uri: uri.to_s,
              range:  Interface::Range.new(
                start: Interface::Position.new(line: loc.start_line - 1, character: loc.start_column),
                end: Interface::Position.new(line: loc.end_line - 1, character: loc.end_column),
              ),
            ),
          )
        end
      end
    end
  end
end
