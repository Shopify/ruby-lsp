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
        $stderr.puts(e.full_message)
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
        Addon.load_addons(@message_queue)

        errored_addons = Addon.addons.select(&:error?)

        if errored_addons.any?
          @message_queue << Notification.new(
            message: "window/showMessage",
            params: Interface::ShowMessageParams.new(
              type: Constant::MessageType::WARNING,
              message: "Error loading addons:\n\n#{errored_addons.map(&:formatted_errors).join("\n\n")}",
            ),
          )

          $stderr.puts(errored_addons.map(&:backtraces).join("\n\n"))
        end

        RubyVM::YJIT.enable if defined? RubyVM::YJIT.enable

        perform_initial_indexing
        check_formatter_is_available

        $stderr.puts("Ruby LSP is ready")
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

        # Run requests for the document
        dispatcher = Prism::Dispatcher.new
        folding_range = Requests::FoldingRanges.new(document.parse_result.comments, dispatcher)
        document_symbol = Requests::DocumentSymbol.new(dispatcher)
        document_link = Requests::DocumentLink.new(uri, document.comments, dispatcher)
        code_lens = Requests::CodeLens.new(uri, dispatcher)

        semantic_highlighting = Requests::SemanticHighlighting.new(dispatcher)
        dispatcher.dispatch(document.tree)

        # Store all responses retrieve in this round of visits in the cache and then return the response for the request
        # we actually received
        document.cache_set("textDocument/foldingRange", folding_range.perform)
        document.cache_set("textDocument/documentSymbol", document_symbol.perform)
        document.cache_set("textDocument/documentLink", document_link.perform)
        document.cache_set("textDocument/codeLens", code_lens.perform)
        document.cache_set(
          "textDocument/semanticTokens/full",
          semantic_highlighting.perform,
        )
        document.cache_get(request[:method])
      when "textDocument/semanticTokens/range"
        semantic_tokens_range(uri, request.dig(:params, :range))
      when "textDocument/formatting"
        begin
          formatting(uri)
        rescue Requests::Formatting::InvalidFormatter => error
          @message_queue << Notification.window_show_error("Configuration error: #{error.message}")
          nil
        rescue StandardError, LoadError => error
          @message_queue << Notification.window_show_error("Formatting error: #{error.message}")
          nil
        end
      when "textDocument/documentHighlight"
        dispatcher = Prism::Dispatcher.new
        document = @store.get(uri)
        request = Requests::DocumentHighlight.new(document, request.dig(:params, :position), dispatcher)
        dispatcher.dispatch(document.tree)
        request.perform
      when "textDocument/onTypeFormatting"
        on_type_formatting(uri, request.dig(:params, :position), request.dig(:params, :ch))
      when "textDocument/hover"
        dispatcher = Prism::Dispatcher.new
        document = @store.get(uri)
        Requests::Hover.new(
          document,
          @index,
          request.dig(:params, :position),
          dispatcher,
          document.typechecker_enabled?,
        ).perform
      when "textDocument/inlayHint"
        hints_configurations = T.must(@store.features_configuration.dig(:inlayHint))
        dispatcher = Prism::Dispatcher.new
        document = @store.get(uri)
        request = Requests::InlayHints.new(document, request.dig(:params, :range), hints_configurations, dispatcher)
        dispatcher.visit(document.tree)
        request.perform
      when "textDocument/codeAction"
        code_action(uri, request.dig(:params, :range), request.dig(:params, :context))
      when "codeAction/resolve"
        code_action_resolve(request.dig(:params))
      when "textDocument/diagnostic"
        begin
          diagnostic(uri)
        rescue StandardError, LoadError => error
          @message_queue << Notification.window_show_error("Error running diagnostics: #{error.message}")
          nil
        end
      when "textDocument/completion"
        dispatcher = Prism::Dispatcher.new
        document = @store.get(uri)
        Requests::Completion.new(
          document,
          @index,
          request.dig(:params, :position),
          document.typechecker_enabled?,
          dispatcher,
        ).perform
      when "textDocument/signatureHelp"
        dispatcher = Prism::Dispatcher.new
        document = @store.get(uri)

        Requests::SignatureHelp.new(
          document,
          @index,
          request.dig(:params, :position),
          request.dig(:params, :context),
          dispatcher,
        ).perform
      when "textDocument/definition"
        dispatcher = Prism::Dispatcher.new
        document = @store.get(uri)
        Requests::Definition.new(
          document,
          @index,
          request.dig(:params, :position),
          dispatcher,
          document.typechecker_enabled?,
        ).perform
      when "workspace/didChangeWatchedFiles"
        did_change_watched_files(request.dig(:params, :changes))
      when "workspace/symbol"
        workspace_symbol(request.dig(:params, :query))
      when "rubyLsp/textDocument/showSyntaxTree"
        show_syntax_tree(uri, request.dig(:params, :range))
      when "rubyLsp/workspace/dependencies"
        workspace_dependencies
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

      Addon.file_watcher_addons.each { |addon| T.unsafe(addon).workspace_did_change_watched_files(changes) }
      VOID
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def workspace_dependencies
      Bundler.with_original_env do
        definition = Bundler.definition
        dep_keys = definition.locked_deps.keys.to_set
        definition.specs.map do |spec|
          {
            name: spec.name,
            version: spec.version,
            path: spec.full_gem_path,
            dependency: dep_keys.include?(spec.name),
          }
        end
      end
    rescue Bundler::GemfileNotFound
      []
    end

    sig { void }
    def perform_initial_indexing
      # The begin progress invocation happens during `initialize`, so that the notification is sent before we are
      # stuck indexing files
      RubyIndexer.configuration.load_config

      Thread.new do
        begin
          @index.index_all do |percentage|
            progress("indexing-progress", percentage)
            true
          rescue ClosedQueueError
            # Since we run indexing on a separate thread, it's possible to kill the server before indexing is complete.
            # In those cases, the message queue will be closed and raise a ClosedQueueError. By returning `false`, we
            # tell the index to stop working immediately
            false
          end
        rescue StandardError => error
          @message_queue << Notification.window_show_error("Error while indexing: #{error.message}")
        end

        # Always end the progress notification even if indexing failed or else it never goes away and the user has no
        # way of dismissing it
        end_progress("indexing-progress")
      end
    end

    sig { params(query: T.nilable(String)).returns(T::Array[Interface::WorkspaceSymbol]) }
    def workspace_symbol(query)
      Requests::WorkspaceSymbol.new(query, @index).perform
    end

    sig { params(uri: URI::Generic, range: T.nilable(T::Hash[Symbol, T.untyped])).returns({ ast: String }) }
    def show_syntax_tree(uri, range)
      { ast: Requests::ShowSyntaxTree.new(@store.get(uri), range).perform }
    end

    sig do
      params(uri: URI::Generic, content_changes: T::Array[T::Hash[Symbol, T.untyped]], version: Integer).returns(Object)
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
        positions: T::Array[T::Hash[Symbol, T.untyped]],
      ).returns(T.nilable(T::Array[T.nilable(Requests::Support::SelectionRange)]))
    end
    def selection_range(uri, positions)
      ranges = @store.cache_fetch(uri, "textDocument/selectionRange") do |document|
        Requests::SelectionRanges.new(document).perform
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

      # Do not format files outside of the workspace. For example, if someone is looking at a gem's source code, we
      # don't want to format it
      path = uri.to_standardized_path
      return unless path.nil? || path.start_with?(T.must(@store.workspace_uri.to_standardized_path))

      Requests::Formatting.new(@store.get(uri), formatter: @store.formatter).perform
    end

    sig do
      params(
        uri: URI::Generic,
        position: T::Hash[Symbol, T.untyped],
        character: String,
      ).returns(T::Array[Interface::TextEdit])
    end
    def on_type_formatting(uri, position, character)
      Requests::OnTypeFormatting.new(@store.get(uri), position, character, @store.client_name).perform
    end

    sig do
      params(
        uri: URI::Generic,
        range: T::Hash[Symbol, T.untyped],
        context: T::Hash[Symbol, T.untyped],
      ).returns(T.nilable(T::Array[Interface::CodeAction]))
    end
    def code_action(uri, range, context)
      document = @store.get(uri)

      Requests::CodeActions.new(document, range, context).perform
    end

    sig { params(params: T::Hash[Symbol, T.untyped]).returns(Interface::CodeAction) }
    def code_action_resolve(params)
      uri = URI(params.dig(:data, :uri))
      document = @store.get(uri)
      result = Requests::CodeActionResolve.new(document, params).perform

      case result
      when Requests::CodeActionResolve::Error::EmptySelection
        @message_queue << Notification.window_show_error("Invalid selection for Extract Variable refactor")
        raise Requests::CodeActionResolve::CodeActionError
      when Requests::CodeActionResolve::Error::InvalidTargetRange
        @message_queue << Notification.window_show_error(
          "Couldn't find an appropriate location to place extracted refactor",
        )
        raise Requests::CodeActionResolve::CodeActionError
      else
        result
      end
    end

    sig { params(uri: URI::Generic).returns(T.nilable(Interface::FullDocumentDiagnosticReport)) }
    def diagnostic(uri)
      # Do not compute diagnostics for files outside of the workspace. For example, if someone is looking at a gem's
      # source code, we don't want to show diagnostics for it
      path = uri.to_standardized_path
      return unless path.nil? || path.start_with?(T.must(@store.workspace_uri.to_standardized_path))

      response = @store.cache_fetch(uri, "textDocument/diagnostic") do |document|
        Requests::Diagnostics.new(document).perform
      end

      Interface::FullDocumentDiagnosticReport.new(kind: "full", items: response) if response
    end

    sig { params(uri: URI::Generic, range: T::Hash[Symbol, T.untyped]).returns(Interface::SemanticTokens) }
    def semantic_tokens_range(uri, range)
      document = @store.get(uri)
      start_line = range.dig(:start, :line)
      end_line = range.dig(:end, :line)

      dispatcher = Prism::Dispatcher.new
      request = Requests::SemanticHighlighting.new(dispatcher, range: start_line..end_line)
      dispatcher.visit(document.tree)

      request.perform
    end

    sig { params(id: String, title: String, percentage: Integer).void }
    def begin_progress(id, title, percentage: 0)
      return unless @store.supports_progress

      @message_queue << Request.new(
        message: "window/workDoneProgress/create",
        params: Interface::WorkDoneProgressCreateParams.new(token: id),
      )

      @message_queue << Notification.new(
        message: "$/progress",
        params: Interface::ProgressParams.new(
          token: id,
          value: Interface::WorkDoneProgressBegin.new(
            kind: "begin",
            title: title,
            percentage: percentage,
            message: "#{percentage}% completed",
          ),
        ),
      )
    end

    sig { params(id: String, percentage: Integer).void }
    def progress(id, percentage)
      return unless @store.supports_progress

      @message_queue << Notification.new(
        message: "$/progress",
        params: Interface::ProgressParams.new(
          token: id,
          value: Interface::WorkDoneProgressReport.new(
            kind: "report",
            percentage: percentage,
            message: "#{percentage}% completed",
          ),
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
    rescue ClosedQueueError
      # If the server was killed and the message queue is already closed, there's no way to end the progress
      # notification
    end

    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def initialize_request(options)
      @store.clear

      workspace_uri = options.dig(:workspaceFolders, 0, :uri)
      @store.workspace_uri = URI(workspace_uri) if workspace_uri

      client_name = options.dig(:clientInfo, :name)
      @store.client_name = client_name if client_name

      encodings = options.dig(:capabilities, :general, :positionEncodings)
      @store.encoding = if encodings.nil? || encodings.empty?
        Constant::PositionEncodingKind::UTF16
      elsif encodings.include?(Constant::PositionEncodingKind::UTF8)
        Constant::PositionEncodingKind::UTF8
      else
        encodings.first
      end

      progress = options.dig(:capabilities, :window, :workDoneProgress)
      @store.supports_progress = progress.nil? ? true : progress
      formatter = options.dig(:initializationOptions, :formatter) || "auto"
      @store.formatter = if formatter == "auto"
        DependencyDetector.instance.detected_formatter
      else
        formatter
      end

      configured_features = options.dig(:initializationOptions, :enabledFeatures)
      @store.experimental_features = options.dig(:initializationOptions, :experimentalFeaturesEnabled) || false

      configured_hints = options.dig(:initializationOptions, :featuresConfiguration, :inlayHint)
      T.must(@store.features_configuration.dig(:inlayHint)).configuration.merge!(configured_hints) if configured_hints

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

      document_symbol_provider = Requests::DocumentSymbol.provider if enabled_features["documentSymbols"]
      document_link_provider = Requests::DocumentLink.provider if enabled_features["documentLink"]
      code_lens_provider = Requests::CodeLens.provider if enabled_features["codeLens"]
      hover_provider = Requests::Hover.provider if enabled_features["hover"]
      folding_ranges_provider = Requests::FoldingRanges.provider if enabled_features["foldingRanges"]
      semantic_tokens_provider = Requests::SemanticHighlighting.provider if enabled_features["semanticHighlighting"]
      diagnostics_provider = Requests::Diagnostics.provider if enabled_features["diagnostics"]
      on_type_formatting_provider = Requests::OnTypeFormatting.provider if enabled_features["onTypeFormatting"]
      code_action_provider = Requests::CodeActions.provider if enabled_features["codeActions"]
      inlay_hint_provider = Requests::InlayHints.provider if enabled_features["inlayHint"]
      completion_provider = Requests::Completion.provider if enabled_features["completion"]
      signature_help_provider = Requests::SignatureHelp.provider if enabled_features["signatureHelp"]

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

      {
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
          signature_help_provider: signature_help_provider,
        ),
        serverInfo: {
          name: "Ruby LSP",
          version: VERSION,
        },
        formatter: @store.formatter,
      }
    end

    sig { void }
    def check_formatter_is_available
      # Warn of an unavailable `formatter` setting, e.g. `rubocop` on a project which doesn't have RuboCop.
      # Syntax Tree will always be available via Ruby LSP so we don't need to check for it.
      return unless @store.formatter == "rubocop"

      unless defined?(RubyLsp::Requests::Support::RuboCopRunner)
        @store.formatter = "none"

        @message_queue << Notification.window_show_error(
          "Ruby LSP formatter is set to `rubocop` but RuboCop was not found in the Gemfile or gemspec.",
        )
      end
    end
  end
end
