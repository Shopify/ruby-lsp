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
        @store = store
        @document = document
        @position = params[:position] #: Hash[Symbol, Integer]
        @new_name = params[:newName] #: String
      end

      # @override
      #: -> Interface::WorkspaceEdit?
      def perform
        char_position, _ = @document.find_index_by_position(@position)

        local_variable_finder = Support::LocalVariableFinder.new(@document.ast)
        local_variable = local_variable_finder.variable_at(char_position, @document.code_units_cache)
        return rename_local_variable(local_variable_finder, local_variable.first) if local_variable

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

        entries = @global_state.index.resolve(name, node_context.nesting)
        return unless entries

        if (conflict_entries = @global_state.index.resolve(@new_name, node_context.nesting))
          raise InvalidNameError, "The new name is already in use by #{conflict_entries.first&.name}"
        end

        fully_qualified_name = entries.first #: as !nil
          .name
        reference_target = RubyIndexer::ReferenceFinder::ConstTarget.new(fully_qualified_name)
        changes = collect_text_edits(reference_target, name)

        # If the client doesn't support resource operations, such as renaming files, then we can only return the basic
        # text changes
        unless @global_state.client_capabilities.supports_rename?
          return Interface::WorkspaceEdit.new(changes: changes)
        end

        # Text edits must be applied before any resource operations, such as renaming files. Otherwise, the file is
        # renamed and then the URI associated to the text edit no longer exists, causing it to be dropped
        document_changes = changes.map do |uri, edits|
          Interface::TextDocumentEdit.new(
            text_document: Interface::VersionedTextDocumentIdentifier.new(uri: uri, version: nil),
            edits: edits,
          )
        end

        collect_file_renames(fully_qualified_name, document_changes)
        Interface::WorkspaceEdit.new(document_changes: document_changes)
      end

      private

      #: (Support::LocalVariableFinder finder, Support::LocalVariableFinder::Variable variable) -> Interface::WorkspaceEdit
      def rename_local_variable(finder, variable)
        if variable.occurrences.any? { |occurrence| occurrence.kind == :keyword_parameter }
          raise InvalidNameError, "Keyword parameters can't be renamed because callers refer to them by name"
        end

        unless valid_local_variable_name?(@new_name)
          raise InvalidNameError, "`#{@new_name}` is not a valid local variable name"
        end

        old_name = variable.name.to_s
        return Interface::WorkspaceEdit.new(changes: {}) if old_name == @new_name

        if finder.name_in_use?(variable, @new_name.to_sym)
          raise InvalidNameError, "The new name is already in use by a local variable or method call in the same scope"
        end

        code_units_cache = @document.code_units_cache
        edits = variable.occurrences.map do |occurrence|
          location = occurrence.location

          if occurrence.kind == :shorthand
            # `{ name: }` has to become `{ name: new_name }`, otherwise the key would change too
            key_location = location.copy(length: location.length + 1)
            Interface::TextEdit.new(
              range: Support::LocalVariableFinder.range_for(key_location, code_units_cache),
              new_text: "#{old_name}: #{@new_name}",
            )
          else
            Interface::TextEdit.new(
              range: Support::LocalVariableFinder.range_for(location, code_units_cache),
              new_text: @new_name,
            )
          end
        end

        Interface::WorkspaceEdit.new(changes: { @document.uri.to_s => edits })
      end

      #: (String name) -> bool
      def valid_local_variable_name?(name)
        result = Prism.parse("#{name} = nil")
        return false unless result.success?

        statements = result.value.statements.body
        return false unless statements.length == 1

        node = statements.first
        return false unless node.is_a?(Prism::LocalVariableWriteNode)

        node.name.to_s == name
      end

      #: (String fully_qualified_name, Array[(Interface::RenameFile | Interface::TextDocumentEdit)] document_changes) -> void
      def collect_file_renames(fully_qualified_name, document_changes)
        # Check if the declarations of the symbol being renamed match the file name. In case they do, we automatically
        # rename the files for the user.
        #
        # We also look for an associated test file and rename it too
        short_name = fully_qualified_name.split("::").last #: as !nil

        @global_state.index[fully_qualified_name]&.each do |entry|
          # Do not rename files that are not part of the workspace
          uri = entry.uri
          file_path = uri.full_path
          next unless file_path&.start_with?(@global_state.workspace_path)

          case entry
          when RubyIndexer::Entry::Class, RubyIndexer::Entry::Module, RubyIndexer::Entry::Constant,
               RubyIndexer::Entry::ConstantAlias, RubyIndexer::Entry::UnresolvedConstantAlias

            file_name = file_from_constant_name(short_name)

            if "#{file_name}.rb" == entry.file_name
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
        end
      end

      #: (RubyIndexer::ReferenceFinder::Target target, String name) -> Hash[String, Array[Interface::TextEdit]]
      def collect_text_edits(target, name)
        changes = {}

        Dir.glob(File.join(@global_state.workspace_path, "**/*.rb")).each do |path|
          uri = URI::Generic.from_path(path: path)
          # If the document is being managed by the client, then we should use whatever is present in the store instead
          # of reading from disk
          next if @store.key?(uri)

          parse_result = Prism.parse_file(path)
          edits = collect_changes(target, parse_result.value, name, uri)
          changes[uri.to_s] = edits unless edits.empty?
        rescue Errno::EISDIR, Errno::ENOENT
          # If `path` is a directory, just ignore it and continue. If the file doesn't exist, then we also ignore it.
        end

        @store.each do |uri, document|
          next unless document.is_a?(RubyDocument) || document.is_a?(ERBDocument)

          edits = collect_changes(target, document.ast, name, document.uri)
          changes[uri] = edits unless edits.empty?
        end

        changes
      end

      #: (RubyIndexer::ReferenceFinder::Target target, Prism::Node ast, String name, URI::Generic uri) -> Array[Interface::TextEdit]
      def collect_changes(target, ast, name, uri)
        dispatcher = Prism::Dispatcher.new
        finder = RubyIndexer::ReferenceFinder.new(target, @global_state.index, dispatcher, uri)
        dispatcher.visit(ast)

        finder.references.map do |reference|
          adjust_reference_for_edit(name, reference)
        end
      end

      #: (String name, RubyIndexer::ReferenceFinder::Reference reference) -> Interface::TextEdit
      def adjust_reference_for_edit(name, reference)
        # The reference may include a namespace in front. We need to check if the rename new name includes namespaces
        # and then adjust both the text and the location to produce the correct edit
        location = reference.location
        new_text = reference.name.sub(name, @new_name)

        Interface::TextEdit.new(range: range_from_location(location), new_text: new_text)
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
