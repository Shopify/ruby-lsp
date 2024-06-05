# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Server < BaseServer
    extend T::Sig

    # Only for testing
    sig { returns(GlobalState) }
    attr_reader :global_state

    sig { params(test_mode: T::Boolean).void }
    def initialize(test_mode: false)
      super
      @global_state = T.let(GlobalState.new, GlobalState)
    end

    sig { override.params(message: T::Hash[Symbol, T.untyped]).void }
    def process_message(message)
      case message[:method]
      when "initialize"
        $stderr.puts("Initializing Ruby LSP v#{VERSION}...")
        run_initialize(message)
      when "initialized"
        $stderr.puts("Finished initializing Ruby LSP!") unless @test_mode
        run_initialized
      when "textDocument/didOpen"
        text_document_did_open(message)
      when "textDocument/didClose"
        text_document_did_close(message)
      when "textDocument/didChange"
        text_document_did_change(message)
      when "textDocument/selectionRange"
        text_document_selection_range(message)
      when "textDocument/documentSymbol"
        text_document_document_symbol(message)
      when "textDocument/documentLink"
        text_document_document_link(message)
      when "textDocument/codeLens"
        text_document_code_lens(message)
      when "textDocument/semanticTokens/full"
        text_document_semantic_tokens_full(message)
      when "textDocument/foldingRange"
        text_document_folding_range(message)
      when "textDocument/semanticTokens/range"
        text_document_semantic_tokens_range(message)
      when "textDocument/formatting"
        text_document_formatting(message)
      when "textDocument/documentHighlight"
        text_document_document_highlight(message)
      when "textDocument/onTypeFormatting"
        text_document_on_type_formatting(message)
      when "textDocument/hover"
        text_document_hover(message)
      when "textDocument/inlayHint"
        text_document_inlay_hint(message)
      when "textDocument/codeAction"
        text_document_code_action(message)
      when "codeAction/resolve"
        code_action_resolve(message)
      when "textDocument/diagnostic"
        text_document_diagnostic(message)
      when "textDocument/completion"
        text_document_completion(message)
      when "completionItem/resolve"
        text_document_completion_item_resolve(message)
      when "textDocument/signatureHelp"
        text_document_signature_help(message)
      when "textDocument/definition"
        text_document_definition(message)
      when "workspace/didChangeWatchedFiles"
        workspace_did_change_watched_files(message)
      when "workspace/symbol"
        workspace_symbol(message)
      when "rubyLsp/textDocument/showSyntaxTree"
        text_document_show_syntax_tree(message)
      when "rubyLsp/workspace/dependencies"
        workspace_dependencies(message)
      when "$/cancelRequest"
        @mutex.synchronize { @cancelled_requests << message[:params][:id] }
      end
    rescue StandardError, LoadError => e
      # If an error occurred in a request, we have to return an error response or else the editor will hang
      if message[:id]
        send_message(Error.new(id: message[:id], code: Constant::ErrorCodes::INTERNAL_ERROR, message: e.full_message))
      end

      $stderr.puts("Error processing #{message[:method]}: #{e.full_message}")
    end

    sig { void }
    def load_addons
      Addon.load_addons(@global_state, @outgoing_queue)
      errored_addons = Addon.addons.select(&:error?)

      if errored_addons.any?
        send_message(
          Notification.new(
            method: "window/showMessage",
            params: Interface::ShowMessageParams.new(
              type: Constant::MessageType::WARNING,
              message: "Error loading addons:\n\n#{errored_addons.map(&:formatted_errors).join("\n\n")}",
            ),
          ),
        )

        $stderr.puts(errored_addons.map(&:errors_details).join("\n\n"))
      end
    end

    private

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def run_initialize(message)
      options = message[:params]
      @global_state.apply_options(options)

      client_name = options.dig(:clientInfo, :name)
      @store.client_name = client_name if client_name

      progress = options.dig(:capabilities, :window, :workDoneProgress)
      @store.supports_progress = progress.nil? ? true : progress
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
        Hash.new(true).merge!(configured_features.transform_keys(&:to_s))
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

      response = {
        capabilities: Interface::ServerCapabilities.new(
          text_document_sync: Interface::TextDocumentSyncOptions.new(
            change: Constant::TextDocumentSyncKind::INCREMENTAL,
            open_close: true,
          ),
          position_encoding: @global_state.encoding_name,
          selection_range_provider: enabled_features["selectionRanges"],
          hover_provider: hover_provider,
          document_symbol_provider: document_symbol_provider,
          document_link_provider: document_link_provider,
          folding_range_provider: folding_ranges_provider,
          semantic_tokens_provider: semantic_tokens_provider,
          document_formatting_provider: enabled_features["formatting"] && @global_state.formatter != "none",
          document_highlight_provider: enabled_features["documentHighlights"],
          code_action_provider: code_action_provider,
          document_on_type_formatting_provider: on_type_formatting_provider,
          diagnostic_provider: diagnostics_provider,
          inlay_hint_provider: inlay_hint_provider,
          completion_provider: completion_provider,
          code_lens_provider: code_lens_provider,
          definition_provider: enabled_features["definition"],
          workspace_symbol_provider: enabled_features["workspaceSymbol"] && !@global_state.typechecker,
          signature_help_provider: signature_help_provider,
        ),
        serverInfo: {
          name: "Ruby LSP",
          version: VERSION,
        },
        formatter: @global_state.formatter,
      }

      send_message(Result.new(id: message[:id], response: response))

      # Not every client supports dynamic registration or file watching
      if global_state.supports_watching_files
        send_message(
          Request.new(
            id: @current_request_id,
            method: "client/registerCapability",
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
    end

    sig { void }
    def run_initialized
      load_addons
      RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)

      indexing_config = {}

      # Need to use the workspace URI, otherwise, this will fail for people working on a project that is a symlink.
      index_path = File.join(@global_state.workspace_path, ".index.yml")

      if File.exist?(index_path)
        begin
          indexing_config = YAML.parse_file(index_path).to_ruby
        rescue Psych::SyntaxError => e
          message = "Syntax error while loading configuration: #{e.message}"
          send_message(
            Notification.new(
              method: "window/showMessage",
              params: Interface::ShowMessageParams.new(
                type: Constant::MessageType::WARNING,
                message: message,
              ),
            ),
          )
        end
      end

      if defined?(Requests::Support::RuboCopFormatter)
        @global_state.register_formatter("rubocop", Requests::Support::RuboCopFormatter.new)
      end
      if defined?(Requests::Support::SyntaxTreeFormatter)
        @global_state.register_formatter("syntax_tree", Requests::Support::SyntaxTreeFormatter.new)
      end

      perform_initial_indexing(indexing_config)
      check_formatter_is_available
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_did_open(message)
      @mutex.synchronize do
        text_document = message.dig(:params, :textDocument)
        @store.set(
          uri: text_document[:uri],
          source: text_document[:text],
          version: text_document[:version],
          encoding: @global_state.encoding,
        )
      end
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_did_close(message)
      @mutex.synchronize do
        uri = message.dig(:params, :textDocument, :uri)
        @store.delete(uri)

        # Clear diagnostics for the closed file, so that they no longer appear in the problems tab
        send_message(
          Notification.new(
            method: "textDocument/publishDiagnostics",
            params: Interface::PublishDiagnosticsParams.new(uri: uri.to_s, diagnostics: []),
          ),
        )
      end
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_did_change(message)
      params = message[:params]
      text_document = params[:textDocument]

      @mutex.synchronize do
        @store.push_edits(uri: text_document[:uri], edits: params[:contentChanges], version: text_document[:version])
      end
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
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
      code_lens = Requests::CodeLens.new(@global_state, uri, dispatcher)

      semantic_highlighting = Requests::SemanticHighlighting.new(@global_state, dispatcher)
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

    alias_method :text_document_document_symbol, :run_combined_requests
    alias_method :text_document_document_link, :run_combined_requests
    alias_method :text_document_code_lens, :run_combined_requests
    alias_method :text_document_semantic_tokens_full, :run_combined_requests
    alias_method :text_document_folding_range, :run_combined_requests

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_semantic_tokens_range(message)
      params = message[:params]
      range = params[:range]
      uri = params.dig(:textDocument, :uri)
      document = @store.get(uri)
      start_line = range.dig(:start, :line)
      end_line = range.dig(:end, :line)

      dispatcher = Prism::Dispatcher.new
      request = Requests::SemanticHighlighting.new(@global_state, dispatcher, range: start_line..end_line)
      dispatcher.visit(document.tree)

      response = request.perform
      send_message(Result.new(id: message[:id], response: response))
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_formatting(message)
      # If formatter is set to `auto` but no supported formatting gem is found, don't attempt to format
      if @global_state.formatter == "none"
        send_empty_response(message[:id])
        return
      end

      uri = message.dig(:params, :textDocument, :uri)
      # Do not format files outside of the workspace. For example, if someone is looking at a gem's source code, we
      # don't want to format it
      path = uri.to_standardized_path
      unless path.nil? || path.start_with?(@global_state.workspace_path)
        send_empty_response(message[:id])
        return
      end

      response = Requests::Formatting.new(@global_state, @store.get(uri)).perform
      send_message(Result.new(id: message[:id], response: response))
    rescue Requests::Request::InvalidFormatter => error
      send_message(Notification.window_show_error("Configuration error: #{error.message}"))
      send_empty_response(message[:id])
    rescue StandardError, LoadError => error
      send_message(Notification.window_show_error("Formatting error: #{error.message}"))
      send_empty_response(message[:id])
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_document_highlight(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))
      request = Requests::DocumentHighlight.new(document, params[:position], dispatcher)
      dispatcher.dispatch(document.tree)
      send_message(Result.new(id: message[:id], response: request.perform))
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
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

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_hover(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::Hover.new(
            document,
            @global_state,
            params[:position],
            dispatcher,
            typechecker_enabled?(document),
          ).perform,
        ),
      )
    end

    sig { params(document: Document).returns(T::Boolean) }
    def typechecker_enabled?(document)
      @global_state.typechecker && document.sorbet_sigil_is_true_or_higher
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_inlay_hint(message)
      params = message[:params]
      hints_configurations = T.must(@store.features_configuration.dig(:inlayHint))
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))
      request = Requests::InlayHints.new(document, params[:range], hints_configurations, dispatcher)
      dispatcher.visit(document.tree)
      send_message(Result.new(id: message[:id], response: request.perform))
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
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

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
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
      when Requests::CodeActionResolve::Error::UnknownCodeAction
        send_message(
          Notification.window_show_error(
            "Unknown code action",
          ),
        )
        raise Requests::CodeActionResolve::CodeActionError
      else
        send_message(Result.new(id: message[:id], response: result))
      end
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_diagnostic(message)
      # Do not compute diagnostics for files outside of the workspace. For example, if someone is looking at a gem's
      # source code, we don't want to show diagnostics for it
      uri = message.dig(:params, :textDocument, :uri)
      path = uri.to_standardized_path
      unless path.nil? || path.start_with?(@global_state.workspace_path)
        send_empty_response(message[:id])
        return
      end

      response = @store.cache_fetch(uri, "textDocument/diagnostic") do |document|
        Requests::Diagnostics.new(@global_state, document).perform
      end

      send_message(
        Result.new(
          id: message[:id],
          response: response && Interface::FullDocumentDiagnosticReport.new(kind: "full", items: response),
        ),
      )
    rescue Requests::Request::InvalidFormatter => error
      send_message(Notification.window_show_error("Configuration error: #{error.message}"))
      send_empty_response(message[:id])
    rescue StandardError, LoadError => error
      send_message(Notification.window_show_error("Error running diagnostics: #{error.message}"))
      send_empty_response(message[:id])
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_completion(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::Completion.new(
            document,
            @global_state,
            params[:position],
            typechecker_enabled?(document),
            dispatcher,
          ).perform,
        ),
      )
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_completion_item_resolve(message)
      send_message(Result.new(
        id: message[:id],
        response: Requests::CompletionResolve.new(@global_state, message[:params]).perform,
      ))
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_signature_help(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::SignatureHelp.new(
            document,
            @global_state,
            params[:position],
            params[:context],
            dispatcher,
            typechecker_enabled?(document),
          ).perform,
        ),
      )
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_definition(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::Definition.new(
            document,
            @global_state,
            params[:position],
            dispatcher,
            typechecker_enabled?(document),
          ).perform,
        ),
      )
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def workspace_did_change_watched_files(message)
      changes = message.dig(:params, :changes)
      index = @global_state.index
      changes.each do |change|
        # File change events include folders, but we're only interested in files
        uri = URI(change[:uri])
        file_path = uri.to_standardized_path
        next if file_path.nil? || File.directory?(file_path)
        next unless file_path.end_with?(".rb")

        load_path_entry = $LOAD_PATH.find { |load_path| file_path.start_with?(load_path) }
        indexable = RubyIndexer::IndexablePath.new(load_path_entry, file_path)

        case change[:type]
        when Constant::FileChangeType::CREATED
          index.index_single(indexable)
        when Constant::FileChangeType::CHANGED
          index.handle_change(indexable)
        when Constant::FileChangeType::DELETED
          index.delete(indexable)
        end
      end

      Addon.file_watcher_addons.each { |addon| T.unsafe(addon).workspace_did_change_watched_files(changes) }
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def workspace_symbol(message)
      send_message(
        Result.new(
          id: message[:id],
          response: Requests::WorkspaceSymbol.new(
            @global_state,
            message.dig(:params, :query),
          ).perform,
        ),
      )
    end

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
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

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
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

    sig { params(config_hash: T::Hash[String, T.untyped]).void }
    def perform_initial_indexing(config_hash)
      # The begin progress invocation happens during `initialize`, so that the notification is sent before we are
      # stuck indexing files
      RubyIndexer.configuration.apply_config(config_hash)

      Thread.new do
        begin
          @global_state.index.index_all do |percentage|
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
        method: "window/workDoneProgress/create",
        params: Interface::WorkDoneProgressCreateParams.new(token: id),
      ))

      send_message(Notification.new(
        method: "$/progress",
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
          method: "$/progress",
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
          method: "$/progress",
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
      return unless @global_state.formatter == "rubocop"

      unless defined?(RubyLsp::Requests::Support::RuboCopRunner)
        @global_state.formatter = "none"

        send_message(
          Notification.window_show_error(
            "Ruby LSP formatter is set to `rubocop` but RuboCop was not found in the Gemfile or gemspec.",
          ),
        )
      end
    end
  end
end
