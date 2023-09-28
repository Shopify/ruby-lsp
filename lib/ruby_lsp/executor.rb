# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests/support/dependency_detector"

module RubyLsp
  # This class dispatches a request execution to the right request class. No IO should happen anywhere here!
  class Executor
    extend T::Sig

    sig { params(store: Store, message_queue: Thread::Queue).void }
    def initialize(store, message_queue)
      # Requests that mutate the store must be run sequentially! Parallel requests only receive a temporary copy of the
      # store
      @store = store
      @message_queue = message_queue
      @index = T.let(RubyIndexer::Index.new, RubyIndexer::Index)
    end

    sig { params(request: T::Hash[Symbol, T.untyped]).returns(Result) }
    def execute(request)
      response = T.let(nil, T.untyped)
      error = T.let(nil, T.nilable(Exception))

      begin
        response = run(request)
      rescue StandardError, LoadError => e
        error = e
      end

      Result.new(response: response, error: error)
    end

    private

    sig { params(request: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
    def run(request)
      uri = URI(request.dig(:params, :textDocument, :uri).to_s)

      case request[:method]
      when "initialize"
        initialize_request(request.dig(:params))
      when "initialized"
        Addon.load_addons

        errored_addons = Addon.addons.select(&:error?)

        if errored_addons.any?
          @message_queue << Notification.new(
            message: "window/showMessage",
            params: Interface::ShowMessageParams.new(
              type: Constant::MessageType::WARNING,
              message: "Error loading addons:\n\n#{errored_addons.map(&:formatted_errors).join("\n\n")}",
            ),
          )

          warn(errored_addons.map(&:backtraces).join("\n\n"))
        end

        perform_initial_indexing
        check_formatter_is_available

        warn("Ruby LSP is ready")
        VOID
      when "textDocument/didOpen"
        text_document_did_open(
          uri,
          request.dig(:params, :textDocument, :text),
          request.dig(:params, :textDocument, :version),
        )
      when "textDocument/didClose"
        @message_queue << Notification.new(
          message: "textDocument/publishDiagnostics",
          params: Interface::PublishDiagnosticsParams.new(uri: uri.to_s, diagnostics: []),
        )

        text_document_did_close(uri)
      when "textDocument/didChange"
        text_document_did_change(
          uri,
          request.dig(:params, :contentChanges),
          request.dig(:params, :textDocument, :version),
        )
      when "textDocument/selectionRange"
        selection_range(uri, request.dig(:params, :positions))
      when "textDocument/documentSymbol", "textDocument/documentLink", "textDocument/codeLens",
           "textDocument/semanticTokens/full", "textDocument/foldingRange"
        document = @store.get(uri)

        # If the response has already been cached by another request, return it
        cached_response = document.cache_get(request[:method])
        return cached_response if cached_response

        # Run listeners for the document
        emitter = EventEmitter.new
        folding_range = Requests::FoldingRanges.new(document.parse_result.comments, emitter, @message_queue)
        document_symbol = Requests::DocumentSymbol.new(emitter, @message_queue)
        document_link = Requests::DocumentLink.new(uri, document.comments, emitter, @message_queue)
        code_lens = Requests::CodeLens.new(uri, emitter, @message_queue)

        semantic_highlighting = Requests::SemanticHighlighting.new(emitter, @message_queue)
        emitter.visit(document.tree)

        # Store all responses retrieve in this round of visits in the cache and then return the response for the request
        # we actually received
        document.cache_set("textDocument/foldingRange", folding_range.response)
        document.cache_set("textDocument/documentSymbol", document_symbol.response)
        document.cache_set("textDocument/documentLink", document_link.response)
        document.cache_set("textDocument/codeLens", code_lens.response)
        document.cache_set(
          "textDocument/semanticTokens/full",
          Requests::Support::SemanticTokenEncoder.new.encode(semantic_highlighting.response),
        )
        document.cache_get(request[:method])
      when "textDocument/semanticTokens/range"
        semantic_tokens_range(uri, request.dig(:params, :range))
      when "textDocument/formatting"
        begin
          formatting(uri)
        rescue Requests::Formatting::InvalidFormatter => error
          @message_queue << Notification.new(
            message: "window/showMessage",
            params: Interface::ShowMessageParams.new(
              type: Constant::MessageType::ERROR,
              message: "Configuration error: #{error.message}",
            ),
          )

          nil
        rescue StandardError, LoadError => error
          @message_queue << Notification.new(
            message: "window/showMessage",
            params: Interface::ShowMessageParams.new(
              type: Constant::MessageType::ERROR,
              message: "Formatting error: #{error.message}",
            ),
          )

          nil
        end
      when "textDocument/documentHighlight"
        document_highlight(uri, request.dig(:params, :position))
      when "textDocument/onTypeFormatting"
        on_type_formatting(uri, request.dig(:params, :position), request.dig(:params, :ch))
      when "textDocument/hover"
        hover(uri, request.dig(:params, :position))
      when "textDocument/inlayHint"
        inlay_hint(uri, request.dig(:params, :range))
      when "textDocument/codeAction"
        code_action(uri, request.dig(:params, :range), request.dig(:params, :context))
      when "codeAction/resolve"
        code_action_resolve(request.dig(:params))
      when "textDocument/diagnostic"
        begin
          diagnostic(uri)
        rescue StandardError, LoadError => error
          @message_queue << Notification.new(
            message: "window/showMessage",
            params: Interface::ShowMessageParams.new(
              type: Constant::MessageType::ERROR,
              message: "Error running diagnostics: #{error.message}",
            ),
          )

          nil
        end
      when "textDocument/completion"
        completion(uri, request.dig(:params, :position))
      when "textDocument/definition"
        definition(uri, request.dig(:params, :position))
      when "workspace/didChangeWatchedFiles"
        did_change_watched_files(request.dig(:params, :changes))
      when "workspace/symbol"
        workspace_symbol(request.dig(:params, :query))
      when "rubyLsp/textDocument/showSyntaxTree"
        show_syntax_tree(uri, request.dig(:params, :range))
      else
        VOID
      end
    end

    sig { params(changes: T::Array[{ uri: String, type: Integer }]).returns(Object) }
    def did_change_watched_files(changes)
      changes.each do |change|
        # File change events include folders, but we're only interested in files
        uri = URI(change[:uri])
        file_path = uri.to_standardized_path
        next if file_path.nil? || File.directory?(file_path)

        load_path_entry = $LOAD_PATH.find { |load_path| file_path.start_with?(load_path) }
        indexable = RubyIndexer::IndexablePath.new(load_path_entry, file_path)

        case change[:type]
        when Constant::FileChangeType::CREATED
          @index.index_single(indexable)
        when Constant::FileChangeType::CHANGED
          @index.delete(indexable)
          @index.index_single(indexable)
        when Constant::FileChangeType::DELETED
          @index.delete(indexable)
        end
      end

      VOID
    end

    sig { void }
    def perform_initial_indexing
      # The begin progress invocation happens during `initialize`, so that the notification is sent before we are
      # stuck indexing files
      RubyIndexer.configuration.load_config

      begin
        @index.index_all
      rescue StandardError => error
        @message_queue << Notification.new(
          message: "window/showMessage",
          params: Interface::ShowMessageParams.new(
            type: Constant::MessageType::ERROR,
            message: "Error while indexing: #{error.message}",
          ),
        )
      end

      # Always end the progress notification even if indexing failed or else it never goes away and the user has no way
      # of dismissing it
      end_progress("indexing-progress")
    end

    sig { params(query: T.nilable(String)).returns(T::Array[Interface::WorkspaceSymbol]) }
    def workspace_symbol(query)
      Requests::WorkspaceSymbol.new(query, @index).run
    end

    sig { params(uri: URI::Generic, range: T.nilable(Document::RangeShape)).returns({ ast: String }) }
    def show_syntax_tree(uri, range)
      { ast: Requests::ShowSyntaxTree.new(@store.get(uri), range).run }
    end

    sig do
      params(
        uri: URI::Generic,
        position: Document::PositionShape,
      ).returns(T.nilable(T.any(T::Array[Interface::Location], Interface::Location)))
    end
    def definition(uri, position)
      document = @store.get(uri)
      target, parent, nesting = document.locate_node(
        position,
        node_types: [YARP::CallNode, YARP::ConstantReadNode, YARP::ConstantPathNode],
      )

      target = parent if target.is_a?(YARP::ConstantReadNode) && parent.is_a?(YARP::ConstantPathNode)

      emitter = EventEmitter.new
      base_listener = Requests::Definition.new(
        uri,
        nesting,
        @index,
        emitter,
        @message_queue,
      )
      emitter.emit_for_target(target)
      base_listener.response
    end

    sig do
      params(
        uri: URI::Generic,
        position: Document::PositionShape,
      ).returns(T.nilable(Interface::Hover))
    end
    def hover(uri, position)
      document = @store.get(uri)
      target, parent, nesting = document.locate_node(
        position,
        node_types: Requests::Hover::ALLOWED_TARGETS,
      )

      if (Requests::Hover::ALLOWED_TARGETS.include?(parent.class) &&
          !Requests::Hover::ALLOWED_TARGETS.include?(target.class)) ||
          (parent.is_a?(YARP::ConstantPathNode) && target.is_a?(YARP::ConstantReadNode))
        target = parent
      end

      # Instantiate all listeners
      emitter = EventEmitter.new
      hover = Requests::Hover.new(@index, nesting, emitter, @message_queue)

      # Emit events for all listeners
      emitter.emit_for_target(target)

      hover.response
    end

    sig do
      params(uri: URI::Generic, content_changes: T::Array[Document::EditShape], version: Integer).returns(Object)
    end
    def text_document_did_change(uri, content_changes, version)
      @store.push_edits(uri: uri, edits: content_changes, version: version)
      VOID
    end

    sig { params(uri: URI::Generic, text: String, version: Integer).returns(Object) }
    def text_document_did_open(uri, text, version)
      @store.set(uri: uri, source: text, version: version)
      VOID
    end

    sig { params(uri: URI::Generic).returns(Object) }
    def text_document_did_close(uri)
      @store.delete(uri)
      VOID
    end

    sig do
      params(
        uri: URI::Generic,
        positions: T::Array[Document::PositionShape],
      ).returns(T.nilable(T::Array[T.nilable(Requests::Support::SelectionRange)]))
    end
    def selection_range(uri, positions)
      ranges = @store.cache_fetch(uri, "textDocument/selectionRange") do |document|
        Requests::SelectionRanges.new(document).run
      end

      # Per the selection range request spec (https://microsoft.github.io/language-server-protocol/specification#textDocument_selectionRange),
      # every position in the positions array should have an element at the same index in the response
      # array. For positions without a valid selection range, the corresponding element in the response
      # array will be nil.

      unless ranges.nil?
        positions.map do |position|
          ranges.find do |range|
            range.cover?(position)
          end
        end
      end
    end

    sig { params(uri: URI::Generic).returns(T.nilable(T::Array[Interface::TextEdit])) }
    def formatting(uri)
      # If formatter is set to `auto` but no supported formatting gem is found, don't attempt to format
      return if @store.formatter == "none"

      Requests::Formatting.new(@store.get(uri), formatter: @store.formatter).run
    end

    sig do
      params(
        uri: URI::Generic,
        position: Document::PositionShape,
        character: String,
      ).returns(T::Array[Interface::TextEdit])
    end
    def on_type_formatting(uri, position, character)
      Requests::OnTypeFormatting.new(@store.get(uri), position, character).run
    end

    sig do
      params(
        uri: URI::Generic,
        position: Document::PositionShape,
      ).returns(T.nilable(T::Array[Interface::DocumentHighlight]))
    end
    def document_highlight(uri, position)
      document = @store.get(uri)

      target, parent = document.locate_node(position)
      emitter = EventEmitter.new
      listener = Requests::DocumentHighlight.new(target, parent, emitter, @message_queue)
      emitter.visit(document.tree)
      listener.response
    end

    sig { params(uri: URI::Generic, range: Document::RangeShape).returns(T.nilable(T::Array[Interface::InlayHint])) }
    def inlay_hint(uri, range)
      document = @store.get(uri)

      start_line = range.dig(:start, :line)
      end_line = range.dig(:end, :line)

      emitter = EventEmitter.new
      listener = Requests::InlayHints.new(start_line..end_line, emitter, @message_queue)
      emitter.visit(document.tree)
      listener.response
    end

    sig do
      params(
        uri: URI::Generic,
        range: Document::RangeShape,
        context: T::Hash[Symbol, T.untyped],
      ).returns(T.nilable(T::Array[Interface::CodeAction]))
    end
    def code_action(uri, range, context)
      document = @store.get(uri)

      Requests::CodeActions.new(document, range, context).run
    end

    sig { params(params: T::Hash[Symbol, T.untyped]).returns(Interface::CodeAction) }
    def code_action_resolve(params)
      uri = URI(params.dig(:data, :uri))
      document = @store.get(uri)
      result = Requests::CodeActionResolve.new(document, params).run

      case result
      when Requests::CodeActionResolve::Error::EmptySelection
        @message_queue << Notification.new(
          message: "window/showMessage",
          params: Interface::ShowMessageParams.new(
            type: Constant::MessageType::ERROR,
            message: "Invalid selection for Extract Variable refactor",
          ),
        )
        raise Requests::CodeActionResolve::CodeActionError
      when Requests::CodeActionResolve::Error::InvalidTargetRange
        @message_queue << Notification.new(
          message: "window/showMessage",
          params: Interface::ShowMessageParams.new(
            type: Constant::MessageType::ERROR,
            message: "Couldn't find an appropriate location to place extracted refactor",
          ),
        )
        raise Requests::CodeActionResolve::CodeActionError
      else
        result
      end
    end

    sig { params(uri: URI::Generic).returns(T.nilable(Interface::FullDocumentDiagnosticReport)) }
    def diagnostic(uri)
      response = @store.cache_fetch(uri, "textDocument/diagnostic") do |document|
        Requests::Diagnostics.new(document).run
      end

      Interface::FullDocumentDiagnosticReport.new(kind: "full", items: response) if response
    end

    sig { params(uri: URI::Generic, range: Document::RangeShape).returns(Interface::SemanticTokens) }
    def semantic_tokens_range(uri, range)
      document = @store.get(uri)
      start_line = range.dig(:start, :line)
      end_line = range.dig(:end, :line)

      emitter = EventEmitter.new
      listener = Requests::SemanticHighlighting.new(
        emitter,
        @message_queue,
        range: start_line..end_line,
      )
      emitter.visit(document.tree)

      Requests::Support::SemanticTokenEncoder.new.encode(listener.response)
    end

    sig do
      params(
        uri: URI::Generic,
        position: Document::PositionShape,
      ).returns(T.nilable(T::Array[Interface::CompletionItem]))
    end
    def completion(uri, position)
      document = @store.get(uri)

      char_position = document.create_scanner.find_char_position(position)

      # When the user types in the first letter of a constant name, we actually receive the position of the next
      # immediate character. We check to see if the character is uppercase and then remove the offset to try to locate
      # the node, as it could not be a constant
      target_node_types = if ("A".."Z").cover?(document.source[char_position - 1])
        char_position -= 1
        [YARP::ConstantReadNode, YARP::ConstantPathNode]
      else
        [YARP::CallNode]
      end

      matched, parent, nesting = document.locate(document.tree, char_position, node_types: target_node_types)
      return unless matched && parent

      target = case matched
      when YARP::CallNode
        message = matched.message
        return unless message == "require"

        args = matched.arguments&.arguments
        return if args.nil? || args.is_a?(YARP::ForwardingArgumentsNode)

        argument = args.first
        return unless argument.is_a?(YARP::StringNode)
        return unless (argument.location.start_offset..argument.location.end_offset).cover?(char_position)

        argument
      when YARP::ConstantReadNode, YARP::ConstantPathNode
        if parent.is_a?(YARP::ConstantPathNode) && matched.is_a?(YARP::ConstantReadNode)
          parent
        else
          matched
        end
      end

      return unless target

      emitter = EventEmitter.new
      listener = Requests::Completion.new(
        @index,
        nesting,
        emitter,
        @message_queue,
      )
      emitter.emit_for_target(target)
      listener.response
    end

    sig { params(id: String, title: String).void }
    def begin_progress(id, title)
      return unless @store.supports_progress

      @message_queue << Request.new(
        message: "window/workDoneProgress/create",
        params: Interface::WorkDoneProgressCreateParams.new(token: id),
      )

      @message_queue << Notification.new(
        message: "$/progress",
        params: Interface::ProgressParams.new(
          token: id,
          value: Interface::WorkDoneProgressBegin.new(kind: "begin", title: title),
        ),
      )
    end

    sig { params(id: String).void }
    def end_progress(id)
      return unless @store.supports_progress

      @message_queue << Notification.new(
        message: "$/progress",
        params: Interface::ProgressParams.new(
          token: id,
          value: Interface::WorkDoneProgressEnd.new(kind: "end"),
        ),
      )
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(Interface::InitializeResult) }
    def initialize_request(options)
      @store.clear

      encodings = options.dig(:capabilities, :general, :positionEncodings)
      @store.encoding = if encodings.nil? || encodings.empty?
        Constant::PositionEncodingKind::UTF16
      elsif encodings.include?(Constant::PositionEncodingKind::UTF8)
        Constant::PositionEncodingKind::UTF8
      else
        encodings.first
      end

      @store.supports_progress = options.dig(:capabilities, :window, :workDoneProgress) || true
      formatter = options.dig(:initializationOptions, :formatter) || "auto"
      @store.formatter = if formatter == "auto"
        DependencyDetector.instance.detected_formatter
      else
        formatter
      end

      configured_features = options.dig(:initializationOptions, :enabledFeatures)
      @store.experimental_features = options.dig(:initializationOptions, :experimentalFeaturesEnabled) || false

      enabled_features = case configured_features
      when Array
        # If the configuration is using an array, then absent features are disabled and present ones are enabled. That's
        # why we use `false` as the default value
        Hash.new(false).merge!(configured_features.to_h { |feature| [feature, true] })
      when Hash
        # If the configuration is already a hash, merge it with a default value of `true`. That way clients don't have
        # to opt-in to every single feature
        Hash.new(true).merge!(configured_features)
      else
        # If no configuration was passed by the client, just enable every feature
        Hash.new(true)
      end

      document_symbol_provider = if enabled_features["documentSymbols"]
        Interface::DocumentSymbolClientCapabilities.new(
          hierarchical_document_symbol_support: true,
          symbol_kind: {
            value_set: (Constant::SymbolKind::FILE..Constant::SymbolKind::TYPE_PARAMETER).to_a,
          },
        )
      end

      document_link_provider = if enabled_features["documentLink"]
        Interface::DocumentLinkOptions.new(resolve_provider: false)
      end

      code_lens_provider = if enabled_features["codeLens"]
        Interface::CodeLensOptions.new(resolve_provider: false)
      end

      hover_provider = if enabled_features["hover"]
        Interface::HoverClientCapabilities.new(dynamic_registration: false)
      end

      folding_ranges_provider = if enabled_features["foldingRanges"]
        Interface::FoldingRangeClientCapabilities.new(line_folding_only: true)
      end

      semantic_tokens_provider = if enabled_features["semanticHighlighting"]
        Interface::SemanticTokensRegistrationOptions.new(
          document_selector: { scheme: "file", language: "ruby" },
          legend: Interface::SemanticTokensLegend.new(
            token_types: Requests::SemanticHighlighting::TOKEN_TYPES.keys,
            token_modifiers: Requests::SemanticHighlighting::TOKEN_MODIFIERS.keys,
          ),
          range: true,
          full: { delta: false },
        )
      end

      diagnostics_provider = if enabled_features["diagnostics"]
        {
          interFileDependencies: false,
          workspaceDiagnostics: false,
        }
      end

      on_type_formatting_provider = if enabled_features["onTypeFormatting"]
        Interface::DocumentOnTypeFormattingOptions.new(
          first_trigger_character: "{",
          more_trigger_character: ["\n", "|"],
        )
      end

      code_action_provider = if enabled_features["codeActions"]
        Interface::CodeActionOptions.new(resolve_provider: true)
      end

      inlay_hint_provider = if enabled_features["inlayHint"]
        Interface::InlayHintOptions.new(resolve_provider: false)
      end

      completion_provider = if enabled_features["completion"]
        Interface::CompletionOptions.new(
          resolve_provider: false,
          trigger_characters: ["/", *"A".."Z"],
          completion_item: {
            labelDetailsSupport: true,
          },
        )
      end

      # Dynamically registered capabilities
      file_watching_caps = options.dig(:capabilities, :workspace, :didChangeWatchedFiles)

      # Not every client supports dynamic registration or file watching
      if file_watching_caps&.dig(:dynamicRegistration) && file_watching_caps&.dig(:relativePatternSupport)
        @message_queue << Request.new(
          message: "client/registerCapability",
          params: Interface::RegistrationParams.new(
            registrations: [
              # Register watching Ruby files
              Interface::Registration.new(
                id: "workspace/didChangeWatchedFiles",
                method: "workspace/didChangeWatchedFiles",
                register_options: Interface::DidChangeWatchedFilesRegistrationOptions.new(
                  watchers: [
                    Interface::FileSystemWatcher.new(
                      glob_pattern: "**/*.rb",
                      kind: Constant::WatchKind::CREATE | Constant::WatchKind::CHANGE | Constant::WatchKind::DELETE,
                    ),
                  ],
                ),
              ),
            ],
          ),
        )
      end

      begin_progress("indexing-progress", "Ruby LSP: indexing files")

      Interface::InitializeResult.new(
        capabilities: Interface::ServerCapabilities.new(
          text_document_sync: Interface::TextDocumentSyncOptions.new(
            change: Constant::TextDocumentSyncKind::INCREMENTAL,
            open_close: true,
          ),
          position_encoding: @store.encoding,
          selection_range_provider: enabled_features["selectionRanges"],
          hover_provider: hover_provider,
          document_symbol_provider: document_symbol_provider,
          document_link_provider: document_link_provider,
          folding_range_provider: folding_ranges_provider,
          semantic_tokens_provider: semantic_tokens_provider,
          document_formatting_provider: enabled_features["formatting"] && formatter != "none",
          document_highlight_provider: enabled_features["documentHighlights"],
          code_action_provider: code_action_provider,
          document_on_type_formatting_provider: on_type_formatting_provider,
          diagnostic_provider: diagnostics_provider,
          inlay_hint_provider: inlay_hint_provider,
          completion_provider: completion_provider,
          code_lens_provider: code_lens_provider,
          definition_provider: enabled_features["definition"],
          workspace_symbol_provider: enabled_features["workspaceSymbol"],
        ),
      )
    end

    sig { void }
    def check_formatter_is_available
      # Warn of an unavailable `formatter` setting, e.g. `rubocop` on a project which doesn't have RuboCop.
      # Syntax Tree will always be available via Ruby LSP so we don't need to check for it.
      return unless @store.formatter == "rubocop"

      unless defined?(RubyLsp::Requests::Support::RuboCopRunner)
        @store.formatter = "none"

        @message_queue << Notification.new(
          message: "window/showMessage",
          params: Interface::ShowMessageParams.new(
            type: Constant::MessageType::ERROR,
            message: "Ruby LSP formatter is set to `rubocop` but RuboCop was not found in the Gemfile or gemspec.",
          ),
        )
      end
    end
  end
end
