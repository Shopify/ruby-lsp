# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Server < BaseServer
    extend T::Sig

    # The instance of the index for this server. Only exposed for tests
    sig { returns(RubyIndexer::Index) }
    attr_reader :index

    sig { void }
    def initialize
      super
      @index = T.let(RubyIndexer::Index.new, RubyIndexer::Index)
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def run_initialize(message)
      options = message[:params]
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
        send_message(
          Request.new(
            id: @current_request_id,
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
          ),
        )
      end

      begin_progress("indexing-progress", "Ruby LSP: indexing files")

      response = {
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

      send_message(Result.new(id: message[:id], response: response))
    end

    sig { override.void }
    def initialized
      Addon.load_addons(@outgoing_queue)
      errored_addons = Addon.addons.select(&:error?)

      if errored_addons.any?
        send_message(
          Notification.new(
            message: "window/showMessage",
            params: Interface::ShowMessageParams.new(
              type: Constant::MessageType::WARNING,
              message: "Error loading addons:\n\n#{errored_addons.map(&:formatted_errors).join("\n\n")}",
            ),
          ),
        )

        $stderr.puts(errored_addons.map(&:backtraces).join("\n\n"))
      end

      RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)

      perform_initial_indexing
      check_formatter_is_available
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_did_open(message)
      text_document = message.dig(:params, :textDocument)
      @store.set(uri: text_document[:uri], source: text_document[:text], version: text_document[:version])
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_did_close(message)
      uri = message.dig(:params, :textDocument, :uri)
      @store.delete(uri)

      # Clear diagnostics for the closed file, so that they no longer appear in the problems tab
      send_message(
        Notification.new(
          message: "textDocument/publishDiagnostics",
          params: Interface::PublishDiagnosticsParams.new(uri: uri.to_s, diagnostics: []),
        ),
      )
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_did_change(message)
      params = message[:params]
      text_document = params[:textDocument]
      @store.push_edits(uri: text_document[:uri], edits: params[:contentChanges], version: text_document[:version])
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_selection_range(message)
      uri = message.dig(:params, :textDocument, :uri)
      ranges = @store.cache_fetch(uri, "textDocument/selectionRange") do |document|
        Requests::SelectionRanges.new(document).perform
      end

      # Per the selection range request spec (https://microsoft.github.io/language-server-protocol/specification#textDocument_selectionRange),
      # every position in the positions array should have an element at the same index in the response
      # array. For positions without a valid selection range, the corresponding element in the response
      # array will be nil.

      response = message.dig(:params, :positions).map do |position|
        ranges.find do |range|
          range.cover?(position)
        end
      end

      send_message(Result.new(id: message[:id], response: response))
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_document_symbol(message)
      run_combined_requests(message)
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_document_link(message)
      run_combined_requests(message)
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_code_lens(message)
      run_combined_requests(message)
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_semantic_tokens_full(message)
      run_combined_requests(message)
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_folding_range(message)
      run_combined_requests(message)
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_semantic_tokens_range(message)
      params = message[:params]
      range = params[:range]
      uri = params.dig(:textDocument, :uri)
      document = @store.get(uri)
      start_line = range.dig(:start, :line)
      end_line = range.dig(:end, :line)

      dispatcher = Prism::Dispatcher.new
      request = Requests::SemanticHighlighting.new(dispatcher, range: start_line..end_line)
      dispatcher.visit(document.tree)

      response = request.perform
      send_message(Result.new(id: message[:id], response: response))
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_formatting(message)
      # If formatter is set to `auto` but no supported formatting gem is found, don't attempt to format
      return if @store.formatter == "none"

      uri = message.dig(:params, :textDocument, :uri)
      # Do not format files outside of the workspace. For example, if someone is looking at a gem's source code, we
      # don't want to format it
      path = uri.to_standardized_path
      return unless path.nil? || path.start_with?(T.must(@store.workspace_uri.to_standardized_path))

      response = Requests::Formatting.new(@store.get(uri), formatter: @store.formatter).perform
      send_message(Result.new(id: message[:id], response: response))
    rescue Requests::Formatting::InvalidFormatter => error
      send_message(Notification.window_show_error("Configuration error: #{error.message}"))
      send_message(Result.new(id: message[:id], response: nil))
    rescue StandardError, LoadError => error
      send_message(Notification.window_show_error("Formatting error: #{error.message}"))
      send_message(Result.new(id: message[:id], response: nil))
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_document_highlight(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))
      request = Requests::DocumentHighlight.new(document, params[:position], dispatcher)
      dispatcher.dispatch(document.tree)
      send_message(Result.new(id: message[:id], response: request.perform))
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_on_type_formatting(message)
      params = message[:params]

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::OnTypeFormatting.new(
            @store.get(params.dig(:textDocument, :uri)),
            params[:position],
            params[:ch],
            @store.client_name,
          ).perform,
        ),
      )
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_hover(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::Hover.new(
            document,
            @index,
            params[:position],
            dispatcher,
            document.typechecker_enabled?,
          ).perform,
        ),
      )
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_inlay_hint(message)
      params = message[:params]
      hints_configurations = T.must(@store.features_configuration.dig(:inlayHint))
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))
      request = Requests::InlayHints.new(document, params[:range], hints_configurations, dispatcher)
      dispatcher.visit(document.tree)
      send_message(Result.new(id: message[:id], response: request.perform))
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_code_action(message)
      params = message[:params]
      document = @store.get(params.dig(:textDocument, :uri))

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::CodeActions.new(
            document,
            params[:range],
            params[:context],
          ).perform,
        ),
      )
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def code_action_resolve(message)
      params = message[:params]
      uri = URI(params.dig(:data, :uri))
      document = @store.get(uri)
      result = Requests::CodeActionResolve.new(document, params).perform

      case result
      when Requests::CodeActionResolve::Error::EmptySelection
        send_message(Notification.window_show_error("Invalid selection for Extract Variable refactor"))
        raise Requests::CodeActionResolve::CodeActionError
      when Requests::CodeActionResolve::Error::InvalidTargetRange
        send_message(
          Notification.window_show_error(
            "Couldn't find an appropriate location to place extracted refactor",
          ),
        )
        raise Requests::CodeActionResolve::CodeActionError
      else
        send_message(Result.new(id: message[:id], response: result))
      end
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_diagnostic(message)
      # Do not compute diagnostics for files outside of the workspace. For example, if someone is looking at a gem's
      # source code, we don't want to show diagnostics for it
      uri = message.dig(:params, :textDocument, :uri)
      path = uri.to_standardized_path
      return unless path.nil? || path.start_with?(T.must(@store.workspace_uri.to_standardized_path))

      response = @store.cache_fetch(uri, "textDocument/diagnostic") do |document|
        Requests::Diagnostics.new(document).perform
      end

      send_message(
        Result.new(
          id: message[:id],
          response: response && Interface::FullDocumentDiagnosticReport.new(kind: "full", items: response),
        ),
      )
    rescue StandardError, LoadError => error
      send_message(Notification.window_show_error("Error running diagnostics: #{error.message}"))
      send_message(Result.new(id: message[:id], response: nil))
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_completion(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::Completion.new(
            document,
            @index,
            params[:position],
            document.typechecker_enabled?,
            dispatcher,
          ).perform,
        ),
      )
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_signature_help(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::SignatureHelp.new(
            document,
            @index,
            params[:position],
            params[:context],
            dispatcher,
          ).perform,
        ),
      )
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_definition(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::Definition.new(
            document,
            @index,
            params[:position],
            dispatcher,
            document.typechecker_enabled?,
          ).perform,
        ),
      )
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def workspace_did_change_watched_files(message)
      changes = message.dig(:params, :changes)
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
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def workspace_symbol(message)
      send_message(
        Result.new(
          id: message[:id],
          response: Requests::WorkspaceSymbol.new(message.dig(:params, :query), @index).perform,
        ),
      )
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_show_syntax_tree(message)
      params = message[:params]
      response = {
        ast: Requests::ShowSyntaxTree.new(
          @store.get(params.dig(:textDocument, :uri)),
          params[:range],
        ).perform,
      }
      send_message(Result.new(id: message[:id], response: response))
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def workspace_dependencies(message)
      response = begin
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

      send_message(Result.new(id: message[:id], response: response))
    end

    sig { override.void }
    def shutdown
      Addon.addons.each(&:deactivate)
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
          send_message(Notification.window_show_error("Error while indexing: #{error.message}"))
        end

        # Always end the progress notification even if indexing failed or else it never goes away and the user has no
        # way of dismissing it
        end_progress("indexing-progress")
      end
    end

    sig { params(id: String, title: String, percentage: Integer).void }
    def begin_progress(id, title, percentage: 0)
      return unless @store.supports_progress

      send_message(Request.new(
        id: @current_request_id,
        message: "window/workDoneProgress/create",
        params: Interface::WorkDoneProgressCreateParams.new(token: id),
      ))

      send_message(Notification.new(
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
      ))
    end

    sig { params(id: String, percentage: Integer).void }
    def progress(id, percentage)
      return unless @store.supports_progress

      send_message(
        Notification.new(
          message: "$/progress",
          params: Interface::ProgressParams.new(
            token: id,
            value: Interface::WorkDoneProgressReport.new(
              kind: "report",
              percentage: percentage,
              message: "#{percentage}% completed",
            ),
          ),
        ),
      )
    end

    sig { params(id: String).void }
    def end_progress(id)
      return unless @store.supports_progress

      send_message(
        Notification.new(
          message: "$/progress",
          params: Interface::ProgressParams.new(
            token: id,
            value: Interface::WorkDoneProgressEnd.new(kind: "end"),
          ),
        ),
      )
    rescue ClosedQueueError
      # If the server was killed and the message queue is already closed, there's no way to end the progress
      # notification
    end

    sig { void }
    def check_formatter_is_available
      # Warn of an unavailable `formatter` setting, e.g. `rubocop` on a project which doesn't have RuboCop.
      # Syntax Tree will always be available via Ruby LSP so we don't need to check for it.
      return unless @store.formatter == "rubocop"

      unless defined?(RubyLsp::Requests::Support::RuboCopRunner)
        @store.formatter = "none"

        send_message(
          Notification.window_show_error(
            "Ruby LSP formatter is set to `rubocop` but RuboCop was not found in the Gemfile or gemspec.",
          ),
        )
      end
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def run_combined_requests(message)
      uri = URI(message.dig(:params, :textDocument, :uri))
      document = @store.get(uri)

      # If the response has already been cached by another request, return it
      cached_response = document.cache_get(message[:method])
      if cached_response
        send_message(Result.new(id: message[:id], response: cached_response))
        return
      end

      # Run requests for the document
      dispatcher = Prism::Dispatcher.new
      folding_range = Requests::FoldingRanges.new(document.parse_result.comments, dispatcher)
      document_symbol = Requests::DocumentSymbol.new(uri, dispatcher)
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
      send_message(Result.new(id: message[:id], response: document.cache_get(message[:method])))
    end
  end
end
