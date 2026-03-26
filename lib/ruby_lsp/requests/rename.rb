# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The
    # [rename](https://microsoft.github.io/language-server-protocol/specification#textDocument_rename)
    # request renames all instances of a symbol in a document.
    class Rename < Request
      include Support::Common

      class InvalidNameError < StandardError; end

      class << self
        #: -> Interface::RenameOptions
        def provider
          Interface::RenameOptions.new(prepare_provider: true)
        end
      end

      #: (GlobalState global_state, Store store, (RubyDocument | ERBDocument) document, Hash[Symbol, untyped] params) -> void
      def initialize(global_state, store, document, params)
        super()
        @global_state = global_state
        @graph = global_state.graph #: Rubydex::Graph
        @store = store
        @document = document
        @position = params[:position] #: Hash[Symbol, Integer]
        @new_name = params[:newName] #: String
      end

      # @override
      #: -> Interface::WorkspaceEdit?
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

        target = target #: as Prism::ConstantReadNode | Prism::ConstantPathNode | Prism::ConstantPathTargetNode

        name = RubyIndexer::Index.constant_name(target)
        return unless name

        declaration = @graph.resolve_constant(name, node_context.nesting)
        return unless declaration

        if (conflict = @graph.resolve_constant(@new_name, node_context.nesting))
          raise InvalidNameError, "The new name is already in use by #{conflict.name}"
        end

        changes = collect_text_edits(declaration, name)

        # If the client doesn't support resource operations, such as renaming files, then we can only return the basic
        # text changes
        unless @global_state.client_capabilities.supports_rename?
          return Interface::WorkspaceEdit.new(changes: changes)
        end

        # Text edits must be applied before any resource operations, such as renaming files. Otherwise, the file is
        # renamed and then the URI associated to the text edit no longer exists, causing it to be dropped
        document_changes = changes.map do |uri, edits|
          Interface::TextDocumentEdit.new(
            text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(uri: uri, version: nil),
            edits: edits,
          )
        end

        collect_file_renames(declaration, document_changes)
        Interface::WorkspaceEdit.new(document_changes: document_changes)
      end

      private

      #: (Rubydex::Declaration, Array[(Interface::RenameFile | Interface::TextDocumentEdit)]) -> void
      def collect_file_renames(declaration, document_changes)
        # Check if the declarations of the symbol being renamed match the file name. In case they do, we automatically
        # rename the files for the user.
        #
        # We also look for an associated test file and rename it too

        unless [
          Rubydex::Class,
          Rubydex::Module,
          Rubydex::Constant,
          Rubydex::ConstantAlias,
        ].any? { |type| declaration.is_a?(type) }
          return
        end

        short_name = declaration.unqualified_name

        declaration.definitions.each do |definition|
          # Do not rename files that are not part of the workspace
          uri = URI(definition.location.uri)
          file_path = uri.full_path
          next unless file_path&.start_with?(@global_state.workspace_path)

          file_name = file_from_constant_name(short_name)
          next unless "#{file_name}.rb" == File.basename(file_path)

          new_file_name = file_from_constant_name(
            @new_name.split("::").last, #: as !nil
          )

          new_uri = URI::Generic.from_path(path: File.join(
            File.dirname(file_path),
            "#{new_file_name}.rb",
          )).to_s

          document_changes << Interface::RenameFile.new(kind: "rename", old_uri: uri.to_s, new_uri: new_uri)
        end
      end

      #: (Rubydex::Declaration declaration, String name) -> Hash[String, Array[Interface::TextEdit]]
      def collect_text_edits(declaration, name)
        changes = {} #: Hash[String, Array[Interface::TextEdit]]
        short_name = name.split("::").last #: as !nil
        new_short_name = @new_name.split("::").last #: as !nil

        # Collect edits for definition sites (where the constant is declared)
        declaration.definitions.each do |definition|
          name_loc = definition.name_location
          next unless name_loc

          uri_string = name_loc.uri
          edits = (changes[uri_string] ||= [])

          # The name_location spans the constant name as written in the definition.
          # We only replace the unqualified name portion (the last segment).
          range = Interface::Range.new(
            start: Interface::Position.new(
              line: name_loc.end_line,
              character: name_loc.end_column - short_name.length,
            ),
            end: Interface::Position.new(line: name_loc.end_line, character: name_loc.end_column),
          )

          edits << Interface::TextEdit.new(range: range, new_text: new_short_name)
        end

        # Collect edits for reference sites (where the constant is used)
        declaration.references.each do |reference|
          ref = reference #: as Rubydex::ConstantReference
          uri_string = ref.location.uri
          edits = (changes[uri_string] ||= [])
          edits << Interface::TextEdit.new(range: ref.to_lsp_range, new_text: new_short_name)
        end

        changes
      end

      #: (String constant_name) -> String
      def file_from_constant_name(constant_name)
        constant_name
          .gsub(/([a-z])([A-Z])|([A-Z])([A-Z][a-z])/, '\1\3_\2\4')
          .downcase
      end
    end
  end
end
