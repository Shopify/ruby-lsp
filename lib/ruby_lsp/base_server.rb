# typed: strict
# frozen_string_literal: true

module RubyLsp
  class BaseServer
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { void }
    def initialize
      @writer = T.let(Transport::Stdio::Writer.new, Transport::Stdio::Writer)
      @reader = T.let(Transport::Stdio::Reader.new, Transport::Stdio::Reader)
      @incoming_queue = T.let(Thread::Queue.new, Thread::Queue)
      @outgoing_queue = T.let(Thread::Queue.new, Thread::Queue)
      @cancelled_requests = T.let([], T::Array[Integer])
      @mutex = T.let(Mutex.new, Mutex)
      @worker = T.let(new_worker, Thread)
      @current_request_id = T.let(1, Integer)
      @store = T.let(Store.new, Store)
      @outgoing_dispatcher = T.let(
        Thread.new do
          while (message = @outgoing_queue.pop)
            @mutex.synchronize { @writer.write(message.to_hash) }
          end
        end,
        Thread,
      )

      Thread.main.priority = 1
    end

    sig { void }
    def start
      @reader.read do |message|
        @mutex.synchronize do
          # We must parse the document under a mutex lock or else we might switch threads and accept text edits in the
          # source. Altering the source reference during parsing will put the parser in an invalid internal state,
          # since it started parsing with one source but then it changed in the middle
          uri = message.dig(:params, :textDocument, :uri)

          if uri
            parsed_uri = URI(uri)
            @store.get(parsed_uri).parse
            message[:params][:textDocument][:uri] = parsed_uri
          end
        end

        @incoming_queue << message
      end
    end

    private

    sig { params(message: T::Hash[Symbol, T.untyped]).void }
    def process_message(message)
      case message[:method]
      when "initialize"
        $stderr.puts("Initializing Ruby LSP v#{VERSION}...")
        run_initialize(message)
      when "initialized"
        $stderr.puts("Finished initializing Ruby LSP!")
        initialized
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
      when "shutdown"
        $stderr.puts("Shutting down Ruby LSP...")

        shutdown

        # Move to implementation
        # Addon.addons.each(&:deactivate)
        # send_message(Result.new(id: message[:id], response: nil))

        @incoming_queue.clear
        @outgoing_queue.clear
        @incoming_queue.close
        @outgoing_queue.close
        @cancelled_requests.clear

        @worker.join
        @outgoing_dispatcher.join
        @store.clear
      when "exit"
        status = @incoming_queue.closed? ? 0 : 1
        $stderr.puts("Shutdown complete with status #{status}")
        exit(status)
      end
    rescue StandardError, LoadError => e
      # If an error occurred in a request, we have to return an error response or else the editor will hang
      if message[:id]
        send_message(Error.new(id: message[:id], code: Constant::ErrorCodes::INTERNAL_ERROR, message: e.full_message))
      end

      $stderr.puts("Error processing #{message[:method]}: #{e.full_message}")
    end

    sig { returns(Thread) }
    def new_worker
      Thread.new do
        while (message = T.let(@incoming_queue.pop, T.nilable(T::Hash[Symbol, T.untyped])))
          id = message[:id]

          # Check if the request was cancelled before trying to process it
          @mutex.synchronize do
            if id && @cancelled_requests.include?(id)
              send_message(Result.new(id: id, response: nil))
              @cancelled_requests.delete(id)
              next
            end
          end

          process_message(message)
        end
      end
    end

    sig { params(message: T.any(Result, Error, Notification, Request)).void }
    def send_message(message)
      @outgoing_queue << message
      @current_request_id += 1 if message.is_a?(Request)
    end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def run_initialize(message); end

    sig { abstract.void }
    def initialized; end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_did_open(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_did_close(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_did_change(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_selection_range(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_document_symbol(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_document_link(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_code_lens(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_semantic_tokens_full(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_folding_range(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_semantic_tokens_range(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_formatting(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_document_highlight(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_on_type_formatting(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_hover(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_inlay_hint(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_code_action(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def code_action_resolve(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_diagnostic(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_completion(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_signature_help(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_definition(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def workspace_did_change_watched_files(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def workspace_symbol(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def text_document_show_syntax_tree(message); end

    sig { abstract.params(message: T::Hash[Symbol, T.untyped]).void }
    def workspace_dependencies(message); end

    sig { abstract.void }
    def shutdown; end
  end
end
