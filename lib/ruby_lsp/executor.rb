# typed: strict
# frozen_string_literal: true

module RubyLsp
  # This class dispatches a request execution to the right request class. No IO should happen anywhere here!
  class Executor
    extend T::Sig

    sig { params(store: Store).void }
    def initialize(store)
      # Requests that mutate the store must be run sequentially! Parallel requests only receive a temporary copy of the
      # store
      @store = store
      @messages = T.let([], T::Array[Message])
    end

    sig { params(request: T::Hash[Symbol, T.untyped]).returns(Result) }
    def execute(request)
      response = T.let(nil, T.untyped)
      error = T.let(nil, T.nilable(Exception))

      request_time = Benchmark.realtime do
        response = run(request)
      rescue StandardError, LoadError => e
        error = e
      end

      Result.new(response: response, error: error, request_time: request_time, messages: @messages)
    end

    private

    sig { params(request: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
    def run(request)
      uri = request.dig(:params, :textDocument, :uri)

      case request[:method]
      when "initialize"
        initialize_request(request.dig(:params))
      when "initialized"
        Extension.load_extensions

        errored_extensions = Extension.extensions.select(&:error?)

        if errored_extensions.any?
          @messages << Notification.new(
            message: "window/showMessage",
            params: Interface::ShowMessageParams.new(
              type: Constant::MessageType::WARNING,
              message: "Error loading extensions:\n\n#{errored_extensions.map(&:formatted_errors).join("\n\n")}",
            ),
          )

          warn(errored_extensions.map(&:backtraces).join("\n\n"))
        end

        warn("Ruby LSP is ready")
        VOID
      when "textDocument/didOpen"
        text_document_did_open(
          uri,
          request.dig(:params, :textDocument, :text),
          request.dig(:params, :textDocument, :version),
        )
      when "textDocument/didClose"
        @messages << Notification.new(
          message: "textDocument/publishDiagnostics",
          params: Interface::PublishDiagnosticsParams.new(uri: uri, diagnostics: []),
        )

        text_document_did_close(uri)
      when "textDocument/didChange"
        text_document_did_change(
          uri,
          request.dig(:params, :contentChanges),
          request.dig(:params, :textDocument, :version),
        )
      when "textDocument/foldingRange"
        folding_range(uri)
      when "textDocument/documentLink"
        document_link(uri)
      when "textDocument/selectionRange"
        selection_range(uri, request.dig(:params, :positions))
      when "textDocument/documentSymbol"
        document_symbol(uri)
      when "textDocument/semanticTokens/full"
        semantic_tokens_full(uri)
      when "textDocument/semanticTokens/range"
        semantic_tokens_range(uri, request.dig(:params, :range))
      when "textDocument/formatting"
        begin
          formatting(uri)
        rescue Requests::Formatting::InvalidFormatter => error
          @messages << Notification.new(
            message: "window/showMessage",
            params: Interface::ShowMessageParams.new(
              type: Constant::MessageType::ERROR,
              message: "Configuration error: #{error.message}",
            ),
          )

          nil
        rescue StandardError => error
          @messages << Notification.new(
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
        rescue StandardError => error
          @messages << Notification.new(
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
      when "textDocument/codeLens"
        code_lens(uri)
      end
    end

    sig { params(uri: String).returns(T::Array[Interface::FoldingRange]) }
    def folding_range(uri)
      @store.cache_fetch(uri, :folding_ranges) do |document|
        Requests::FoldingRanges.new(document).run
      end
    end

    sig { params(uri: String).returns(T::Array[Interface::CodeLens]) }
    def code_lens(uri)
      @store.cache_fetch(uri, :code_lens) do |document|
        Requests::CodeLens.new(document).run
      end
    end

    sig do
      params(
        uri: String,
        position: Document::PositionShape,
      ).returns(T.nilable(Interface::Hover))
    end
    def hover(uri, position)
      document = @store.get(uri)
      document.parse
      return if document.syntax_error?

      target, parent = document.locate_node(position)

      if !Requests::Hover::ALLOWED_TARGETS.include?(target.class) &&
          Requests::Hover::ALLOWED_TARGETS.include?(parent.class)
        target = parent
      end

      # Instantiate all listeners
      base_listener = Requests::Hover.new
      listeners = Requests::Hover.listeners.map(&:new)

      # Emit events for all listeners
      T.unsafe(EventEmitter).new(base_listener, *listeners).emit_for_target(target)

      # Merge all responses into a single hover
      listeners.each { |ext| base_listener.merge_response!(ext) }
      base_listener.response
    end

    sig { params(uri: String).returns(T::Array[Interface::DocumentLink]) }
    def document_link(uri)
      @store.cache_fetch(uri, :document_link) do |document|
        RubyLsp::Requests::DocumentLink.new(document).run
      end
    end

    sig { params(uri: String).returns(T::Array[Interface::DocumentSymbol]) }
    def document_symbol(uri)
      @store.cache_fetch(uri, :document_symbol) do |document|
        Requests::DocumentSymbol.new(document).run
      end
    end

    sig { params(uri: String, content_changes: T::Array[Document::EditShape], version: Integer).returns(Object) }
    def text_document_did_change(uri, content_changes, version)
      @store.push_edits(uri: uri, edits: content_changes, version: version)
      VOID
    end

    sig { params(uri: String, text: String, version: Integer).returns(Object) }
    def text_document_did_open(uri, text, version)
      @store.set(uri: uri, source: text, version: version)
      VOID
    end

    sig { params(uri: String).returns(Object) }
    def text_document_did_close(uri)
      @store.delete(uri)
      VOID
    end

    sig do
      params(
        uri: String,
        positions: T::Array[Document::PositionShape],
      ).returns(T.nilable(T::Array[T.nilable(Requests::Support::SelectionRange)]))
    end
    def selection_range(uri, positions)
      ranges = @store.cache_fetch(uri, :selection_ranges) do |document|
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

    sig { params(uri: String).returns(Interface::SemanticTokens) }
    def semantic_tokens_full(uri)
      @store.cache_fetch(uri, :semantic_highlighting) do |document|
        T.cast(
          Requests::SemanticHighlighting.new(
            document,
            encoder: Requests::Support::SemanticTokenEncoder.new,
          ).run,
          Interface::SemanticTokens,
        )
      end
    end

    sig { params(uri: String).returns(T.nilable(T::Array[Interface::TextEdit])) }
    def formatting(uri)
      Requests::Formatting.new(@store.get(uri), formatter: @store.formatter).run
    end

    sig do
      params(
        uri: String,
        position: Document::PositionShape,
        character: String,
      ).returns(T::Array[Interface::TextEdit])
    end
    def on_type_formatting(uri, position, character)
      Requests::OnTypeFormatting.new(@store.get(uri), position, character).run
    end

    sig do
      params(
        uri: String,
        position: Document::PositionShape,
      ).returns(T::Array[Interface::DocumentHighlight])
    end
    def document_highlight(uri, position)
      Requests::DocumentHighlight.new(@store.get(uri), position).run
    end

    sig { params(uri: String, range: Document::RangeShape).returns(T::Array[Interface::InlayHint]) }
    def inlay_hint(uri, range)
      document = @store.get(uri)
      start_line = range.dig(:start, :line)
      end_line = range.dig(:end, :line)

      Requests::InlayHints.new(document, start_line..end_line).run
    end

    sig do
      params(
        uri: String,
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
      uri = params.dig(:data, :uri)
      document = @store.get(uri)
      result = Requests::CodeActionResolve.new(document, params).run

      case result
      when Requests::CodeActionResolve::Error::EmptySelection
        @messages << Notification.new(
          message: "window/showMessage",
          params: Interface::ShowMessageParams.new(
            type: Constant::MessageType::ERROR,
            message: "Invalid selection for Extract Variable refactor",
          ),
        )
        raise Requests::CodeActionResolve::CodeActionError
      when Requests::CodeActionResolve::Error::InvalidTargetRange
        @messages << Notification.new(
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

    sig { params(uri: String).returns(T.nilable(Interface::FullDocumentDiagnosticReport)) }
    def diagnostic(uri)
      response = @store.cache_fetch(uri, :diagnostics) do |document|
        Requests::Diagnostics.new(document).run
      end

      Interface::FullDocumentDiagnosticReport.new(kind: "full", items: response.map(&:to_lsp_diagnostic)) if response
    end

    sig { params(uri: String, range: Document::RangeShape).returns(Interface::SemanticTokens) }
    def semantic_tokens_range(uri, range)
      document = @store.get(uri)
      start_line = range.dig(:start, :line)
      end_line = range.dig(:end, :line)

      T.cast(
        Requests::SemanticHighlighting.new(
          document,
          range: start_line..end_line,
          encoder: Requests::Support::SemanticTokenEncoder.new,
        ).run,
        Interface::SemanticTokens,
      )
    end

    sig do
      params(uri: String, position: Document::PositionShape).returns(T.nilable(T::Array[Interface::CompletionItem]))
    end
    def completion(uri, position)
      Requests::PathCompletion.new(@store.get(uri), position).run
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

      formatter = options.dig(:initializationOptions, :formatter)
      @store.formatter = formatter unless formatter.nil?

      configured_features = options.dig(:initializationOptions, :enabledFeatures)
      experimental_features = options.dig(:initializationOptions, :experimentalFeaturesEnabled)

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
            value_set: Requests::DocumentSymbol::SYMBOL_KIND.values,
          },
        )
      end

      document_link_provider = if enabled_features["documentLink"]
        Interface::DocumentLinkOptions.new(resolve_provider: false)
      end

      code_lens_provider = if experimental_features
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
          trigger_characters: ["/"],
        )
      end

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
        ),
      )
    end
  end
end
