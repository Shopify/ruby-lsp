# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Server < BaseServer
    # Only for testing
    #: GlobalState
    attr_reader :global_state

    # @override
    #: (Hash[Symbol, untyped] message) -> void
    def process_message(message)
      case message[:method]
      when "initialize"
        send_log_message("Initializing Ruby LSP v#{VERSION} https://github.com/Shopify/ruby-lsp/releases/tag/v#{VERSION}....")
        run_initialize(message)
      when "initialized"
        send_log_message("Finished initializing Ruby LSP!") unless @test_mode

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
      when "codeLens/resolve"
        code_lens_resolve(message)
      when "textDocument/semanticTokens/full"
        text_document_semantic_tokens_full(message)
      when "textDocument/semanticTokens/full/delta"
        text_document_semantic_tokens_delta(message)
      when "textDocument/foldingRange"
        text_document_folding_range(message)
      when "textDocument/semanticTokens/range"
        text_document_semantic_tokens_range(message)
      when "textDocument/formatting"
        text_document_formatting(message)
      when "textDocument/rangeFormatting"
        text_document_range_formatting(message)
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
      when "textDocument/prepareTypeHierarchy"
        text_document_prepare_type_hierarchy(message)
      when "textDocument/rename"
        text_document_rename(message)
      when "textDocument/prepareRename"
        text_document_prepare_rename(message)
      when "textDocument/references"
        text_document_references(message)
      when "typeHierarchy/supertypes"
        type_hierarchy_supertypes(message)
      when "typeHierarchy/subtypes"
        type_hierarchy_subtypes(message)
      when "workspace/didChangeWatchedFiles"
        workspace_did_change_watched_files(message)
      when "workspace/symbol"
        workspace_symbol(message)
      when "rubyLsp/textDocument/showSyntaxTree"
        text_document_show_syntax_tree(message)
      when "rubyLsp/workspace/dependencies"
        workspace_dependencies(message)
      when "rubyLsp/workspace/addons"
        send_message(
          Result.new(
            id: message[:id],
            response:
              Addon.addons.map do |addon|
                version = begin
                  addon.version
                rescue AbstractMethodInvokedError
                  nil
                end

                { name: addon.name, version: version, errored: addon.error? }
              end,
          ),
        )
      when "rubyLsp/composeBundle"
        compose_bundle(message)
      when "rubyLsp/diagnoseState"
        diagnose_state(message)
      when "rubyLsp/discoverTests"
        discover_tests(message)
      when "rubyLsp/resolveTestCommands"
        resolve_test_commands(message)
      when "experimental/goToRelevantFile"
        experimental_go_to_relevant_file(message)
      when "$/cancelRequest"
        @global_state.synchronize { @cancelled_requests << message[:params][:id] }
      when nil
        process_response(message) if message[:result]
      end
    rescue DelegateRequestError
      send_message(Error.new(id: message[:id], code: DelegateRequestError::CODE, message: "DELEGATE_REQUEST"))
    rescue StandardError, LoadError, SystemExit => e
      # If an error occurred in a request, we have to return an error response or else the editor will hang
      if message[:id]
        # If a document is deleted before we are able to process all of its enqueued requests, we will try to read it
        # from disk and it raise this error. This is expected, so we don't include the `data` attribute to avoid
        # reporting these to our telemetry.
        #
        # Similarly, if we receive a location for an invalid position in the
        # document, we don't report it to telemetry
        case e
        when Store::NonExistingDocumentError, Document::InvalidLocationError
          send_message(Error.new(
            id: message[:id],
            code: Constant::ErrorCodes::INVALID_PARAMS,
            message: e.full_message,
          ))
        else
          send_message(Error.new(
            id: message[:id],
            code: Constant::ErrorCodes::INTERNAL_ERROR,
            message: e.full_message,
            data: {
              errorClass: e.class.name,
              errorMessage: e.message,
              backtrace: e.backtrace&.join("\n"),
            },
          ))
        end
      end

      send_log_message("Error processing #{message[:method]}: #{e.full_message}", type: Constant::MessageType::ERROR)
    end

    # Process responses to requests that were sent to the client
    #: (Hash[Symbol, untyped] message) -> void
    def process_response(message)
      case message.dig(:result, :method)
      when "window/showMessageRequest"
        window_show_message_request(message)
      end
    end

    #: (?include_project_addons: bool) -> void
    def load_addons(include_project_addons: true)
      # If invoking Bundler.setup failed, then the load path will not be configured properly and trying to load add-ons
      # with Gem.find_files will find every single version installed of an add-on, leading to requiring several
      # different versions of the same files. We cannot load add-ons if Bundler.setup failed
      return if @setup_error

      errors = Addon.load_addons(@global_state, @outgoing_queue, include_project_addons: include_project_addons)
      return if test_mode?

      if errors.any?
        send_log_message(
          "Error loading addons:\n\n#{errors.map(&:full_message).join("\n\n")}",
          type: Constant::MessageType::WARNING,
        )
      end

      errored_addons = Addon.addons.select(&:error?)

      if errored_addons.any?
        send_message(
          Notification.window_show_message(
            "Error loading add-ons:\n\n#{errored_addons.map(&:formatted_errors).join("\n\n")}",
            type: Constant::MessageType::WARNING,
          ),
        )

        send_log_message(errored_addons.map(&:errors_details).join("\n\n"), type: Constant::MessageType::WARNING)
      end
    end

    private

    #: (Hash[Symbol, untyped] message) -> void
    def run_initialize(message)
      options = message[:params]
      global_state_notifications = @global_state.apply_options(options)

      client_name = options.dig(:clientInfo, :name)
      @store.client_name = client_name if client_name

      configured_features = options.dig(:initializationOptions, :enabledFeatures)

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

      bundle_env_path = File.join(".ruby-lsp", "bundle_env")
      bundle_env = if File.exist?(bundle_env_path)
        env = File.readlines(bundle_env_path).to_h do |line|
          line.chomp.split("=", 2) #: as [String, String]
        end
        FileUtils.rm(bundle_env_path)
        env
      end

      document_symbol_provider = Requests::DocumentSymbol.provider if enabled_features["documentSymbols"]
      document_link_provider = Requests::DocumentLink.provider if enabled_features["documentLink"]
      code_lens_provider = Requests::CodeLens.provider if enabled_features["codeLens"]
      hover_provider = Requests::Hover.provider if enabled_features["hover"]
      folding_ranges_provider = Requests::FoldingRanges.provider if enabled_features["foldingRanges"]
      semantic_tokens_provider = Requests::SemanticHighlighting.provider if enabled_features["semanticHighlighting"]
      document_formatting_provider = Requests::Formatting.provider if enabled_features["formatting"]
      diagnostics_provider = Requests::Diagnostics.provider if enabled_features["diagnostics"]
      on_type_formatting_provider = Requests::OnTypeFormatting.provider if enabled_features["onTypeFormatting"]
      code_action_provider = Requests::CodeActions.provider if enabled_features["codeActions"]
      inlay_hint_provider = Requests::InlayHints.provider if enabled_features["inlayHint"]
      completion_provider = Requests::Completion.provider if enabled_features["completion"]
      signature_help_provider = Requests::SignatureHelp.provider if enabled_features["signatureHelp"]
      type_hierarchy_provider = Requests::PrepareTypeHierarchy.provider if enabled_features["typeHierarchy"]
      rename_provider = Requests::Rename.provider unless @global_state.has_type_checker

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
          document_formatting_provider: document_formatting_provider && @global_state.formatter != "none",
          document_highlight_provider: enabled_features["documentHighlights"],
          code_action_provider: code_action_provider,
          document_on_type_formatting_provider: on_type_formatting_provider,
          diagnostic_provider: diagnostics_provider,
          inlay_hint_provider: inlay_hint_provider,
          completion_provider: completion_provider,
          code_lens_provider: code_lens_provider,
          definition_provider: enabled_features["definition"],
          workspace_symbol_provider: enabled_features["workspaceSymbol"] && !@global_state.has_type_checker,
          signature_help_provider: signature_help_provider,
          type_hierarchy_provider: type_hierarchy_provider,
          rename_provider: rename_provider,
          references_provider: !@global_state.has_type_checker,
          document_range_formatting_provider: true,
          experimental: {
            addon_detection: true,
            compose_bundle: true,
            go_to_relevant_file: true,
            full_test_discovery: true,
          },
        ),
        serverInfo: {
          name: "Ruby LSP",
          version: VERSION,
        },
        formatter: @global_state.formatter,
        degraded_mode: !!(@install_error || @setup_error),
        bundle_env: bundle_env,
      }

      send_message(Result.new(id: message[:id], response: response))

      # Not every client supports dynamic registration or file watching
      if @global_state.client_capabilities.supports_watching_files
        send_message(Request.register_watched_files(
          @current_request_id,
          "**/*.rb",
          registration_id: "workspace-watcher",
        ))

        send_message(Request.register_watched_files(
          @current_request_id,
          Interface::RelativePattern.new(
            base_uri: @global_state.workspace_uri.to_s,
            pattern: "{.rubocop.yml,.rubocop,.rubocop_todo.yml}",
          ),
          registration_id: "rubocop-watcher",
        ))
      end

      process_indexing_configuration(options.dig(:initializationOptions, :indexing))

      begin_progress("indexing-progress", "Ruby LSP: indexing files")

      global_state_notifications.each { |notification| send_message(notification) }

      if @setup_error
        send_message(Notification.telemetry(
          type: "error",
          errorMessage: @setup_error.message,
          errorClass: @setup_error.class,
          stack: @setup_error.backtrace&.join("\n"),
        ))
      end

      if @install_error
        send_message(Notification.telemetry(
          type: "error",
          errorMessage: @install_error.message,
          errorClass: @install_error.class,
          stack: @install_error.backtrace&.join("\n"),
        ))
      end
    end

    #: -> void
    def run_initialized
      load_addons
      RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)

      unless @setup_error
        if defined?(Requests::Support::RuboCopFormatter)
          begin
            @global_state.register_formatter("rubocop_internal", Requests::Support::RuboCopFormatter.new)
          rescue ::RuboCop::Error => e
            # The user may have provided unknown config switches in .rubocop or
            # is trying to load a non-existent config file.
            send_message(Notification.window_show_message(
              "RuboCop configuration error: #{e.message}. Formatting will not be available.",
              type: Constant::MessageType::ERROR,
            ))
          end
        end
        if defined?(Requests::Support::SyntaxTreeFormatter)
          @global_state.register_formatter("syntax_tree", Requests::Support::SyntaxTreeFormatter.new)
        end
      end

      perform_initial_indexing
      check_formatter_is_available
      update_server if @global_state.enabled_feature?(:launcher)
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_did_open(message)
      text_document = message.dig(:params, :textDocument)
      language_id = case text_document[:languageId]
      when "erb", "eruby"
        :erb
      when "rbs"
        :rbs
      else
        :ruby
      end

      document = @store.set(
        uri: text_document[:uri],
        source: text_document[:text],
        version: text_document[:version],
        language_id: language_id,
      )

      if document.past_expensive_limit? && text_document[:uri].scheme == "file"
        log_message = <<~MESSAGE
          The file #{text_document[:uri].path} is too long. For performance reasons, semantic highlighting and
          diagnostics will be disabled.
        MESSAGE

        send_message(
          Notification.new(
            method: "window/logMessage",
            params: Interface::LogMessageParams.new(
              type: Constant::MessageType::WARNING,
              message: log_message,
            ),
          ),
        )
      end
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_did_close(message)
      uri = message.dig(:params, :textDocument, :uri)
      @store.delete(uri)

      # Clear diagnostics for the closed file, so that they no longer appear in the problems tab
      send_message(Notification.publish_diagnostics(uri.to_s, []))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_did_change(message)
      params = message[:params]
      text_document = params[:textDocument]

      @store.push_edits(uri: text_document[:uri], edits: params[:contentChanges], version: text_document[:version])
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_selection_range(message)
      uri = message.dig(:params, :textDocument, :uri)
      ranges = @store.cache_fetch(uri, "textDocument/selectionRange") do |document|
        case document
        when RubyDocument, ERBDocument
          Requests::SelectionRanges.new(document).perform
        else
          []
        end
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

    #: (Hash[Symbol, untyped] message) -> void
    def run_combined_requests(message)
      uri = URI(message.dig(:params, :textDocument, :uri))
      document = @store.get(uri)

      unless document.is_a?(RubyDocument) || document.is_a?(ERBDocument)
        send_empty_response(message[:id])
        return
      end

      # If the response has already been cached by another request, return it
      cached_response = document.cache_get(message[:method])
      if cached_response != Document::EMPTY_CACHE
        send_message(Result.new(id: message[:id], response: cached_response))
        return
      end

      parse_result = document.parse_result

      # Run requests for the document
      dispatcher = Prism::Dispatcher.new
      folding_range = Requests::FoldingRanges.new(parse_result.comments, dispatcher)
      document_symbol = Requests::DocumentSymbol.new(uri, dispatcher)
      document_link = Requests::DocumentLink.new(uri, parse_result.comments, dispatcher)
      inlay_hint = Requests::InlayHints.new(
        @global_state,
        document,
        dispatcher,
      )

      # The code lens listener requires the index to be populated, so the DeclarationListener must be inserted first in
      # the dispatcher's state
      code_lens = nil #: Requests::CodeLens?

      if document.is_a?(RubyDocument) && document.should_index?
        # Re-index the file as it is modified. This mode of indexing updates entries only. Require path trees are only
        # updated on save
        @global_state.synchronize do
          send_log_message("Determined that document should be indexed: #{uri}")

          @global_state.index.handle_change(uri) do |index|
            index.delete(uri, skip_require_paths_tree: true)
            RubyIndexer::DeclarationListener.new(index, dispatcher, parse_result, uri, collect_comments: true)
            code_lens = Requests::CodeLens.new(@global_state, document, dispatcher)
            dispatcher.dispatch(document.ast)
          end
        end
      else
        code_lens = Requests::CodeLens.new(@global_state, document, dispatcher)
        dispatcher.dispatch(document.ast)
      end

      # Store all responses retrieve in this round of visits in the cache and then return the response for the request
      # we actually received
      document.cache_set("textDocument/foldingRange", folding_range.perform)
      document.cache_set("textDocument/documentSymbol", document_symbol.perform)
      document.cache_set("textDocument/documentLink", document_link.perform)
      document.cache_set(
        "textDocument/codeLens",
        code_lens #: as !nil
          .perform,
      )
      document.cache_set("textDocument/inlayHint", inlay_hint.perform)

      send_message(Result.new(id: message[:id], response: document.cache_get(message[:method])))
    end

    alias_method :text_document_document_symbol, :run_combined_requests
    alias_method :text_document_document_link, :run_combined_requests
    alias_method :text_document_code_lens, :run_combined_requests
    alias_method :text_document_folding_range, :run_combined_requests

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_semantic_tokens_full(message)
      document = @store.get(message.dig(:params, :textDocument, :uri))

      if document.past_expensive_limit?
        send_empty_response(message[:id])
        return
      end

      unless document.is_a?(RubyDocument) || document.is_a?(ERBDocument)
        send_empty_response(message[:id])
        return
      end

      dispatcher = Prism::Dispatcher.new
      semantic_highlighting = Requests::SemanticHighlighting.new(@global_state, dispatcher, document, nil)
      dispatcher.visit(document.ast)

      send_message(Result.new(id: message[:id], response: semantic_highlighting.perform))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_semantic_tokens_delta(message)
      document = @store.get(message.dig(:params, :textDocument, :uri))

      if document.past_expensive_limit?
        send_empty_response(message[:id])
        return
      end

      unless document.is_a?(RubyDocument) || document.is_a?(ERBDocument)
        send_empty_response(message[:id])
        return
      end

      dispatcher = Prism::Dispatcher.new
      request = Requests::SemanticHighlighting.new(
        @global_state,
        dispatcher,
        document,
        message.dig(:params, :previousResultId),
      )
      dispatcher.visit(document.ast)
      send_message(Result.new(id: message[:id], response: request.perform))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_semantic_tokens_range(message)
      params = message[:params]
      range = params[:range]
      uri = params.dig(:textDocument, :uri)
      document = @store.get(uri)

      if document.past_expensive_limit?
        send_empty_response(message[:id])
        return
      end

      unless document.is_a?(RubyDocument) || document.is_a?(ERBDocument)
        send_empty_response(message[:id])
        return
      end

      dispatcher = Prism::Dispatcher.new
      request = Requests::SemanticHighlighting.new(
        @global_state,
        dispatcher,
        document,
        nil,
        range: range.dig(:start, :line)..range.dig(:end, :line),
      )
      dispatcher.visit(document.ast)
      send_message(Result.new(id: message[:id], response: request.perform))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_range_formatting(message)
      # If formatter is set to `auto` but no supported formatting gem is found, don't attempt to format
      if @global_state.formatter == "none"
        send_empty_response(message[:id])
        return
      end

      params = message[:params]
      uri = params.dig(:textDocument, :uri)
      # Do not format files outside of the workspace. For example, if someone is looking at a gem's source code, we
      # don't want to format it
      path = uri.to_standardized_path
      unless path.nil? || path.start_with?(@global_state.workspace_path)
        send_empty_response(message[:id])
        return
      end

      document = @store.get(uri)
      unless document.is_a?(RubyDocument)
        send_empty_response(message[:id])
        return
      end

      response = Requests::RangeFormatting.new(@global_state, document, params).perform
      send_message(Result.new(id: message[:id], response: response))
    end

    #: (Hash[Symbol, untyped] message) -> void
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
        send_log_message(<<~MESSAGE)
          Ignoring formatting request for file outside of the workspace.
          Workspace path was set by editor as #{@global_state.workspace_path}.
          File path requested for formatting was #{path}
        MESSAGE
        send_empty_response(message[:id])
        return
      end

      document = @store.get(uri)
      unless document.is_a?(RubyDocument)
        send_empty_response(message[:id])
        return
      end

      response = Requests::Formatting.new(@global_state, document).perform
      send_message(Result.new(id: message[:id], response: response))
    rescue Requests::Request::InvalidFormatter => error
      send_message(Notification.window_show_message(
        "Configuration error: #{error.message}",
        type: Constant::MessageType::ERROR,
      ))
      send_empty_response(message[:id])
    rescue StandardError, LoadError => error
      send_message(Notification.window_show_message(
        "Formatting error: #{error.message}",
        type: Constant::MessageType::ERROR,
      ))
      send_message(Notification.window_log_message(
        "Formatting failed with\r\n: #{error.full_message}",
        type: Constant::MessageType::ERROR,
      ))
      send_empty_response(message[:id])
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_document_highlight(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))

      unless document.is_a?(RubyDocument) || document.is_a?(ERBDocument)
        send_empty_response(message[:id])
        return
      end

      request = Requests::DocumentHighlight.new(@global_state, document, params[:position], dispatcher)
      dispatcher.dispatch(document.ast)
      send_message(Result.new(id: message[:id], response: request.perform))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_on_type_formatting(message)
      params = message[:params]
      document = @store.get(params.dig(:textDocument, :uri))

      unless document.is_a?(RubyDocument)
        send_empty_response(message[:id])
        return
      end

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::OnTypeFormatting.new(
            document,
            params[:position],
            params[:ch],
            @store.client_name,
          ).perform,
        ),
      )
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_hover(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))

      unless document.is_a?(RubyDocument) || document.is_a?(ERBDocument)
        send_empty_response(message[:id])
        return
      end

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::Hover.new(
            document,
            @global_state,
            params[:position],
            dispatcher,
            sorbet_level(document),
          ).perform,
        ),
      )
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_rename(message)
      params = message[:params]
      document = @store.get(params.dig(:textDocument, :uri))

      unless document.is_a?(RubyDocument)
        send_empty_response(message[:id])
        return
      end

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::Rename.new(@global_state, @store, document, params).perform,
        ),
      )
    rescue Requests::Rename::InvalidNameError => e
      send_message(Error.new(id: message[:id], code: Constant::ErrorCodes::REQUEST_FAILED, message: e.message))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_prepare_rename(message)
      params = message[:params]
      document = @store.get(params.dig(:textDocument, :uri))

      unless document.is_a?(RubyDocument)
        send_empty_response(message[:id])
        return
      end

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::PrepareRename.new(document, params[:position]).perform,
        ),
      )
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_references(message)
      params = message[:params]
      document = @store.get(params.dig(:textDocument, :uri))

      unless document.is_a?(RubyDocument)
        send_empty_response(message[:id])
        return
      end

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::References.new(@global_state, @store, document, params).perform,
        ),
      )
    end

    #: (Document[untyped] document) -> SorbetLevel
    def sorbet_level(document)
      return SorbetLevel.ignore unless document.is_a?(RubyDocument)
      return SorbetLevel.ignore unless @global_state.has_type_checker

      sigil = document.parse_result.magic_comments.find do |comment|
        comment.key == "typed"
      end&.value

      SorbetLevel.new(sigil)
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_inlay_hint(message)
      params = message[:params]
      document = @store.get(params.dig(:textDocument, :uri))
      range = params.dig(:range, :start, :line)..params.dig(:range, :end, :line)

      cached_response = document.cache_get("textDocument/inlayHint")
      if cached_response != Document::EMPTY_CACHE

        send_message(
          Result.new(
            id: message[:id],
            response: cached_response.select { |hint| range.cover?(hint.position[:line]) },
          ),
        )
        return
      end

      dispatcher = Prism::Dispatcher.new

      unless document.is_a?(RubyDocument) || document.is_a?(ERBDocument)
        send_empty_response(message[:id])
        return
      end

      request = Requests::InlayHints.new(@global_state, document, dispatcher)
      dispatcher.visit(document.ast)
      result = request.perform
      document.cache_set("textDocument/inlayHint", result)

      send_message(Result.new(id: message[:id], response: result.select { |hint| range.cover?(hint.position[:line]) }))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_code_action(message)
      params = message[:params]
      document = @store.get(params.dig(:textDocument, :uri))

      unless document.is_a?(RubyDocument) || document.is_a?(ERBDocument)
        send_empty_response(message[:id])
        return
      end

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

    #: (Hash[Symbol, untyped] message) -> void
    def code_action_resolve(message)
      params = message[:params]
      uri = URI(params.dig(:data, :uri))
      document = @store.get(uri)

      unless document.is_a?(RubyDocument)
        fail_request_and_notify(message[:id], "Code actions are currently only available for Ruby documents")
        return
      end

      result = Requests::CodeActionResolve.new(document, @global_state, params).perform
      send_message(Result.new(id: message[:id], response: result))
    rescue Requests::CodeActionResolve::CodeActionError => e
      fail_request_and_notify(message[:id], e.message)
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_diagnostic(message)
      # Do not compute diagnostics for files outside of the workspace. For example, if someone is looking at a gem's
      # source code, we don't want to show diagnostics for it
      uri = message.dig(:params, :textDocument, :uri)
      path = uri.to_standardized_path
      unless path.nil? || path.start_with?(@global_state.workspace_path)
        send_empty_response(message[:id])
        return
      end

      document = @store.get(uri)

      response = document.cache_fetch("textDocument/diagnostic") do |document|
        case document
        when RubyDocument
          Requests::Diagnostics.new(@global_state, document).perform
        end
      end

      send_message(
        Result.new(
          id: message[:id],
          response: response && Interface::FullDocumentDiagnosticReport.new(kind: "full", items: response),
        ),
      )
    rescue Requests::Request::InvalidFormatter => error
      send_message(Notification.window_show_message(
        "Configuration error: #{error.message}",
        type: Constant::MessageType::ERROR,
      ))
      send_empty_response(message[:id])
    rescue StandardError, LoadError => error
      send_message(Notification.window_show_message(
        "Error running diagnostics: #{error.message}",
        type: Constant::MessageType::ERROR,
      ))
      send_message(Notification.window_log_message(
        "Diagnostics failed with\r\n: #{error.full_message}",
        type: Constant::MessageType::ERROR,
      ))
      send_empty_response(message[:id])
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_completion(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))

      unless document.is_a?(RubyDocument) || document.is_a?(ERBDocument)
        send_empty_response(message[:id])
        return
      end

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::Completion.new(
            document,
            @global_state,
            params,
            sorbet_level(document),
            dispatcher,
          ).perform,
        ),
      )
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_completion_item_resolve(message)
      # When responding to a delegated completion request, it means we're handling a completion item that isn't related
      # to Ruby (probably related to an ERB host language like HTML). We need to return the original completion item
      # back to the editor so that it's displayed correctly
      if message.dig(:params, :data, :delegateCompletion)
        send_message(Result.new(
          id: message[:id],
          response: message[:params],
        ))
        return
      end

      send_message(Result.new(
        id: message[:id],
        response: Requests::CompletionResolve.new(@global_state, message[:params]).perform,
      ))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_signature_help(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))

      unless document.is_a?(RubyDocument) || document.is_a?(ERBDocument)
        send_empty_response(message[:id])
        return
      end

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::SignatureHelp.new(
            document,
            @global_state,
            params[:position],
            params[:context],
            dispatcher,
            sorbet_level(document),
          ).perform,
        ),
      )
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_definition(message)
      params = message[:params]
      dispatcher = Prism::Dispatcher.new
      document = @store.get(params.dig(:textDocument, :uri))

      unless document.is_a?(RubyDocument) || document.is_a?(ERBDocument)
        send_empty_response(message[:id])
        return
      end

      send_message(
        Result.new(
          id: message[:id],
          response: Requests::Definition.new(
            document,
            @global_state,
            params[:position],
            dispatcher,
            sorbet_level(document),
          ).perform,
        ),
      )
    end

    #: (Hash[Symbol, untyped] message) -> void
    def workspace_did_change_watched_files(message)
      # If indexing is not complete yet, delay processing did change watched file notifications. We need initial
      # indexing to be in place so that we can handle file changes appropriately without risking duplicates. We also
      # have to sleep before re-inserting the notification in the queue otherwise the worker can get stuck in its own
      # loop of pushing and popping the same notification
      unless @global_state.index.initial_indexing_completed
        Thread.new do
          sleep(2)
          # We have to ensure that the queue is not closed yet, since nothing stops the user from saving a file and then
          # immediately telling the LSP to shutdown
          @incoming_queue << message unless @incoming_queue.closed?
        end

        return
      end

      changes = message.dig(:params, :changes)
      # We allow add-ons to register for watching files and we have no restrictions for what they register for. If the
      # same pattern is registered more than once, the LSP will receive duplicate change notifications. Receiving them
      # is fine, but we shouldn't process the same file changes more than once
      changes.uniq!

      index = @global_state.index
      changes.each do |change|
        # File change events include folders, but we're only interested in files
        uri = URI(change[:uri])
        file_path = uri.to_standardized_path
        next if file_path.nil? || File.directory?(file_path)

        if file_path.end_with?(".rb")
          handle_ruby_file_change(index, file_path, change[:type])
          next
        end

        file_name = File.basename(file_path)

        if file_name == ".rubocop.yml" || file_name == ".rubocop" || file_name == ".rubocop_todo.yml"
          handle_rubocop_config_change(uri)
        end
      end

      Addon.file_watcher_addons.each do |addon|
        addon #: as untyped
          .workspace_did_change_watched_files(changes)
      rescue => e
        send_log_message(
          "Error in #{addon.name} add-on while processing watched file notifications: #{e.full_message}",
          type: Constant::MessageType::ERROR,
        )
      end
    end

    #: (RubyIndexer::Index index, String file_path, Integer change_type) -> void
    def handle_ruby_file_change(index, file_path, change_type)
      @global_state.synchronize do
        load_path_entry = $LOAD_PATH.find { |load_path| file_path.start_with?(load_path) }
        uri = URI::Generic.from_path(load_path_entry: load_path_entry, path: file_path)

        case change_type
        when Constant::FileChangeType::CREATED
          content = File.read(file_path)
          # If we receive a late created notification for a file that has already been claimed by the client, we want to
          # handle change for that URI so that the require path tree is updated
          @store.key?(uri) ? index.handle_change(uri, content) : index.index_single(uri, content)
        when Constant::FileChangeType::CHANGED
          content = File.read(file_path)
          # We only handle changes on file watched notifications if the client is not the one managing this URI.
          # Otherwise, these changes are handled when running the combined requests
          index.handle_change(uri, content) unless @store.key?(uri)
        when Constant::FileChangeType::DELETED
          index.delete(uri)
        end
      rescue Errno::ENOENT
        # If a file is created and then delete immediately afterwards, we will process the created notification before
        # we receive the deleted one, but the file no longer exists. This may happen when running a test suite that
        # creates and deletes files automatically.
      end
    end

    #: (URI::Generic uri) -> void
    def handle_rubocop_config_change(uri)
      return unless defined?(Requests::Support::RuboCopFormatter)

      # Register a new runner to reload configurations
      @global_state.register_formatter("rubocop_internal", Requests::Support::RuboCopFormatter.new)

      # Clear all document caches for pull diagnostics
      @store.each { |_uri, document| document.clear_cache("textDocument/diagnostic") }

      # Request a pull diagnostic refresh from the editor
      if @global_state.client_capabilities.supports_diagnostic_refresh
        send_message(Request.new(id: @current_request_id, method: "workspace/diagnostic/refresh", params: nil))
      end
    end

    #: (Hash[Symbol, untyped] message) -> void
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

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_show_syntax_tree(message)
      params = message[:params]
      document = @store.get(params.dig(:textDocument, :uri))

      unless document.is_a?(RubyDocument)
        send_empty_response(message[:id])
        return
      end

      response = {
        ast: Requests::ShowSyntaxTree.new(
          document,
          params[:range],
        ).perform,
      }
      send_message(Result.new(id: message[:id], response: response))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def experimental_go_to_relevant_file(message)
      path = message.dig(:params, :textDocument, :uri).to_standardized_path
      unless path.nil? || path.start_with?(@global_state.workspace_path)
        send_empty_response(message[:id])
        return
      end

      unless path
        send_empty_response(message[:id])
        return
      end

      response = {
        locations: Requests::GoToRelevantFile.new(path, @global_state.workspace_path).perform,
      }
      send_message(Result.new(id: message[:id], response: response))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def text_document_prepare_type_hierarchy(message)
      params = message[:params]
      document = @store.get(params.dig(:textDocument, :uri))

      unless document.is_a?(RubyDocument) || document.is_a?(ERBDocument)
        send_empty_response(message[:id])
        return
      end

      response = Requests::PrepareTypeHierarchy.new(
        document,
        @global_state.index,
        params[:position],
      ).perform

      send_message(Result.new(id: message[:id], response: response))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def type_hierarchy_supertypes(message)
      response = Requests::TypeHierarchySupertypes.new(
        @global_state.index,
        message.dig(:params, :item),
      ).perform
      send_message(Result.new(id: message[:id], response: response))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def type_hierarchy_subtypes(message)
      # TODO: implement subtypes
      # The current index representation doesn't allow us to find the children of an entry.
      send_message(Result.new(id: message[:id], response: nil))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def workspace_dependencies(message)
      unless @global_state.top_level_bundle
        send_message(Result.new(id: message[:id], response: []))
        return
      end

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
      rescue Bundler::GemNotFound, Bundler::GemfileNotFound
        []
      end

      send_message(Result.new(id: message[:id], response: response))
    end

    # @override
    #: -> void
    def shutdown
      Addon.unload_addons
    end

    #: -> void
    def perform_initial_indexing
      # The begin progress invocation happens during `initialize`, so that the notification is sent before we are
      # stuck indexing files
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
          message = "Error while indexing (see [troubleshooting steps]" \
            "(https://shopify.github.io/ruby-lsp/troubleshooting#indexing)): #{error.message}"
          send_message(Notification.window_show_message(message, type: Constant::MessageType::ERROR))
        end

        # Indexing produces a high number of short lived object allocations. That might lead to some fragmentation and
        # an unnecessarily expanded heap. Compacting ensures that the heap is as small as possible and that future
        # allocations and garbage collections are faster
        GC.compact unless @test_mode

        @global_state.synchronize do
          # If we linearize ancestors while the index is not fully populated, we may end up caching incorrect results
          # that were missing namespaces. After indexing is complete, we need to clear the ancestors cache and start
          # again
          @global_state.index.clear_ancestors

          # The results for code lens depend on ancestor linearization, so we need to clear any previously computed
          # responses
          @store.each { |_uri, document| document.clear_cache("textDocument/codeLens") }
        end

        # Always end the progress notification even if indexing failed or else it never goes away and the user has no
        # way of dismissing it
        end_progress("indexing-progress")

        # Request a code lens refresh if we populated them before all test parent classes were indexed
        if @global_state.client_capabilities.supports_code_lens_refresh
          send_message(Request.new(id: @current_request_id, method: "workspace/codeLens/refresh", params: nil))
        end
      end
    end

    #: (String id, String title, ?percentage: Integer) -> void
    def begin_progress(id, title, percentage: 0)
      return unless @global_state.client_capabilities.supports_progress

      send_message(Request.new(
        id: @current_request_id,
        method: "window/workDoneProgress/create",
        params: Interface::WorkDoneProgressCreateParams.new(token: id),
      ))

      send_message(Notification.progress_begin(id, title, percentage: percentage, message: "#{percentage}% completed"))
    end

    #: (String id, Integer percentage) -> void
    def progress(id, percentage)
      return unless @global_state.client_capabilities.supports_progress

      send_message(Notification.progress_report(id, percentage: percentage, message: "#{percentage}% completed"))
    end

    #: (String id) -> void
    def end_progress(id)
      return unless @global_state.client_capabilities.supports_progress

      send_message(Notification.progress_end(id))
    rescue ClosedQueueError
      # If the server was killed and the message queue is already closed, there's no way to end the progress
      # notification
    end

    #: -> void
    def check_formatter_is_available
      return if @setup_error
      # Warn of an unavailable `formatter` setting, e.g. `rubocop_internal` on a project which doesn't have RuboCop.
      return unless @global_state.formatter == "rubocop_internal"

      unless defined?(RubyLsp::Requests::Support::RuboCopRunner)
        @global_state.formatter = "none"

        send_message(
          Notification.window_show_message(
            "Ruby LSP formatter is set to `rubocop_internal` but RuboCop was not found in the Gemfile or gemspec.",
            type: Constant::MessageType::ERROR,
          ),
        )
      end
    end

    #: (Hash[Symbol, untyped]? indexing_options) -> void
    def process_indexing_configuration(indexing_options)
      # Need to use the workspace URI, otherwise, this will fail for people working on a project that is a symlink.
      index_path = File.join(@global_state.workspace_path, ".index.yml")

      if File.exist?(index_path)
        begin
          @global_state.index.configuration.apply_config(YAML.parse_file(index_path).to_ruby)
          send_message(
            Notification.new(
              method: "window/showMessage",
              params: Interface::ShowMessageParams.new(
                type: Constant::MessageType::WARNING,
                message: "The .index.yml configuration file is deprecated. " \
                  "Please use editor settings to configure the index",
              ),
            ),
          )
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
        return
      end

      configuration = @global_state.index.configuration
      configuration.workspace_path = @global_state.workspace_path
      return unless indexing_options

      # The index expects snake case configurations, but VS Code standardizes on camel case settings
      configuration.apply_config(indexing_options.transform_keys { |key| key.to_s.gsub(/([A-Z])/, "_\\1").downcase })
    end

    #: (Hash[Symbol, untyped] message) -> void
    def window_show_message_request(message)
      result = message[:result]
      return unless result

      addon_name = result[:addon_name]
      addon = Addon.addons.find { |addon| addon.name == addon_name }
      return unless addon

      addon.handle_window_show_message_response(result[:title])
    end

    # NOTE: all servers methods are void because they can produce several messages for the client. The only reason this
    # method returns the created thread is to that we can join it in tests and avoid flakiness. The implementation is
    # not supposed to rely on the return of this method
    #: (Hash[Symbol, untyped] message) -> Thread?
    def compose_bundle(message)
      already_composed_path = File.join(@global_state.workspace_path, ".ruby-lsp", "bundle_is_composed")
      id = message[:id]

      begin
        Bundler.with_original_env do
          Bundler::LockfileParser.new(Bundler.default_lockfile.read)
        end
      rescue Bundler::LockfileError => e
        send_message(Error.new(id: id, code: BUNDLE_COMPOSE_FAILED_CODE, message: e.message))
        return
      rescue Bundler::GemfileNotFound, Errno::ENOENT
        # We still compose the bundle if there's no Gemfile or if the lockfile got deleted
      end

      # We compose the bundle in a thread so that the LSP continues to work while we're checking for its validity. Once
      # we return the response back to the editor, then the restart is triggered
      launch_bundle_compose("Recomposing the bundle ahead of restart") do |stderr, status|
        if status&.exitstatus == 0
          # Create a signal for the restart that it can skip composing the bundle and launch directly
          FileUtils.touch(already_composed_path)
          send_message(Result.new(id: id, response: { success: true }))
        else
          # This special error code makes the extension avoid restarting in case we already know that the composed
          # bundle is not valid
          send_message(
            Error.new(id: id, code: BUNDLE_COMPOSE_FAILED_CODE, message: "Failed to compose bundle\n#{stderr}"),
          )
        end
      end
    end

    #: -> void
    def update_server
      return unless File.exist?(File.join(@global_state.workspace_path, ".ruby-lsp", "needs_update"))

      launch_bundle_compose("Trying to update server") do |stderr, status|
        if status&.exitstatus == 0
          send_log_message("Successfully updated the server")
        else
          send_log_message("Failed to update server\n#{stderr}", type: Constant::MessageType::ERROR)
        end
      end
    end

    #: (String) { (IO, Process::Status?) -> void } -> Thread
    def launch_bundle_compose(log, &block)
      Thread.new do
        send_log_message(log)

        _stdout, stderr, status = Bundler.with_unbundled_env do
          Open3.capture3(
            Gem.ruby,
            "-I",
            File.dirname(
              __dir__, #: as !nil
            ),
            File.expand_path("../../exe/ruby-lsp-launcher", __dir__),
            @global_state.workspace_uri.to_s,
            chdir: @global_state.workspace_path,
          )
        end

        block.call(stderr, status)
      end
    end

    # Returns internal state information for debugging purposes
    #: (Hash[Symbol, untyped] message) -> void
    def diagnose_state(message)
      documents = {}
      @store.each { |uri, document| documents[uri] = document.source }

      send_message(
        Result.new(
          id: message[:id],
          response: {
            workerAlive: @worker.alive?,
            backtrace: @worker.backtrace,
            documents: documents,
            incomingQueueSize: @incoming_queue.length,
          },
        ),
      )
    end

    # Discovers all available test groups and examples in a given file taking into consideration the merged response of
    # all add-ons
    #: (Hash[Symbol, untyped] message) -> void
    def discover_tests(message)
      document = @store.get(message.dig(:params, :textDocument, :uri))

      unless document.is_a?(RubyDocument)
        send_empty_response(message[:id])
        return
      end

      cached_response = document.cache_get("rubyLsp/discoverTests")
      if cached_response != Document::EMPTY_CACHE
        send_message(Result.new(id: message[:id], response: cached_response.map(&:to_hash)))
        return
      end

      items = Requests::DiscoverTests.new(@global_state, document, Prism::Dispatcher.new).perform
      document.cache_set("rubyLsp/discoverTests", items)

      send_message(Result.new(id: message[:id], response: items.map(&:to_hash)))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def resolve_test_commands(message)
      items = message.dig(:params, :items)
      commands = Listeners::TestStyle.resolve_test_commands(items)

      Addon.addons.each do |addon|
        commands.concat(addon.resolve_test_commands(items))
      end

      send_message(Result.new(
        id: message[:id],
        response: { commands: commands },
      ))
    end

    #: (Hash[Symbol, untyped] message) -> void
    def code_lens_resolve(message)
      code_lens = message[:params]
      args = code_lens.dig(:data, :arguments)

      case code_lens.dig(:data, :kind)
      when "run_test"
        code_lens[:command] = Interface::Command.new(title: "▶ Run", command: "rubyLsp.runTest", arguments: args)
      when "run_test_in_terminal"
        code_lens[:command] =
          Interface::Command.new(title: "▶ Run in terminal", command: "rubyLsp.runTestInTerminal", arguments: args)
      when "debug_test"
        code_lens[:command] = Interface::Command.new(title: "⚙ Debug", command: "rubyLsp.debugTest", arguments: args)
      end

      send_message(Result.new(
        id: message[:id],
        response: code_lens,
      ))
    end
  end
end
