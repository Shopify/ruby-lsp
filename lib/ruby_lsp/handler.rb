# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests"
require "ruby_lsp/store"
require "ruby_lsp/queue"

module RubyLsp
  Interface = LanguageServer::Protocol::Interface
  Constant = LanguageServer::Protocol::Constant
  Transport = LanguageServer::Protocol::Transport

  class Handler
    extend T::Sig
    VOID = T.let(Object.new.freeze, Object)

    class RequestHandler < T::Struct
      extend T::Sig

      const :action, T.proc.params(request: T::Hash[Symbol, T.untyped]).returns(T.untyped)
      const :parallel, T::Boolean
      prop :error_handler,
        T.nilable(T.proc.params(error: Exception, request: T::Hash[Symbol, T.untyped]).void)

      # A proc that runs in case a request has errored. Receives the error and the original request as arguments. Useful
      # for displaying window messages on errors
      sig do
        params(
          block: T.proc.bind(Handler).params(error: Exception, request: T::Hash[Symbol, T.untyped]).void,
        ).void
      end
      def on_error(&block)
        self.error_handler = block
      end
    end

    class << self
      extend T::Sig

      sig { params(blk: T.proc.bind(Handler).params(arg0: T.untyped).void).void }
      def start(&blk)
        handler = new
        handler.instance_exec(&blk)
        handler.start
      end
    end

    sig { returns(Store) }
    attr_reader :store

    sig { void }
    def initialize
      @writer = T.let(Transport::Stdio::Writer.new, Transport::Stdio::Writer)
      @reader = T.let(Transport::Stdio::Reader.new, Transport::Stdio::Reader)
      @handlers = T.let({}, T::Hash[String, RequestHandler])
      @store = T.let(Store.new, Store)
      @queue = T.let(Queue.new(@writer, @handlers), Queue)
    end

    sig { void }
    def start
      $stderr.puts "Starting Ruby LSP..."

      @reader.read do |request|
        handler = @handlers[request[:method]]
        next if handler.nil?

        if handler.parallel
          @queue.push(request)
        else
          result = @queue.execute(request)
          @queue.finalize_request(result, request)
        end
      end
    end

    private

    sig { params(id: T.any(String, Integer)).void }
    def cancel_request(id)
      @queue.cancel(id)
    end

    sig do
      params(
        msg: String,
        parallel: T::Boolean,
        blk: T.proc.bind(Handler).params(request: T::Hash[Symbol, T.untyped]).returns(T.untyped),
      ).returns(RequestHandler)
    end
    def on(msg, parallel: false, &blk)
      @handlers[msg] = RequestHandler.new(action: blk, parallel: parallel)
    end

    sig { void }
    def shutdown
      $stderr.puts "Shutting down Ruby LSP..."
      @queue.shutdown
      store.clear
    end

    sig { params(uri: String).void }
    def clear_diagnostics(uri)
      @writer.write(
        method: "textDocument/publishDiagnostics",
        params: Interface::PublishDiagnosticsParams.new(uri: uri, diagnostics: []),
      )
    end

    sig { params(type: Integer, message: String).void }
    def show_message(type, message)
      @writer.write(
        method: "window/showMessage",
        params: Interface::ShowMessageParams.new(type: type, message: message),
      )
    end
  end
end
