# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests"
require "ruby_lsp/store"
require "ruby_lsp/queue"
require "benchmark"

module RubyLsp
  Interface = LanguageServer::Protocol::Interface
  Constant = LanguageServer::Protocol::Constant
  Transport = LanguageServer::Protocol::Transport

  class Handler
    extend T::Sig
    VOID = T.let(Object.new.freeze, Object)

    class RequestHandler < T::Struct
      const :action, T.proc.params(request: T::Hash[Symbol, T.untyped]).returns(T.untyped)
      const :parallel, T::Boolean
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
      @queue = T.let(Queue.new, Queue)
    end

    sig { void }
    def start
      $stderr.puts "Starting Ruby LSP..."

      @reader.read do |request|
        handler = @handlers[request[:method]]
        next if handler.nil?

        if handler.parallel
          @queue.push(request) { |request| handle(request) }
        else
          handle(request)
        end
      end
    end

    private

    # The client still expects a response for cancelled requests, so we return nil
    sig { params(id: T.any(String, Integer)).void }
    def cancel_request(id)
      @queue.cancel(id)
      @writer.write(id: id, result: nil)
    end

    sig do
      params(
        msg: String,
        parallel: T::Boolean,
        blk: T.proc.bind(Handler).params(request: T::Hash[Symbol, T.untyped]).returns(T.untyped)
      ).void
    end
    def on(msg, parallel: false, &blk)
      @handlers[msg] = RequestHandler.new(action: blk, parallel: parallel)
    end

    sig { params(request: T::Hash[Symbol, T.untyped]).void }
    def handle(request)
      result = T.let(nil, T.untyped)
      error = T.let(nil, T.nilable(StandardError))
      handler = T.must(@handlers[request[:method]])

      request_time = Benchmark.realtime do
        begin
          result = handler.action.call(request)
        rescue StandardError => e
          error = e
        end

        if error
          @writer.write(
            id: request[:id],
            error: {
              code: Constant::ErrorCodes::INTERNAL_ERROR,
              message: error.inspect,
              data: request.to_json,
            },
          )
        elsif result != VOID
          @writer.write(id: request[:id], result: result)
        end
      end

      @writer.write(method: "telemetry/event", params: telemetry_params(request, request_time, error))
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
        params: Interface::PublishDiagnosticsParams.new(uri: uri, diagnostics: [])
      )
    end

    sig { params(type: Integer, message: String).void }
    def show_message(type, message)
      @writer.write(
        method: "window/showMessage",
        params: Interface::ShowMessageParams.new(type: type, message: message)
      )
    end

    sig do
      params(
        request: T::Hash[Symbol, T.untyped],
        request_time: Float,
        error: T.nilable(StandardError)
      ).returns(T::Hash[Symbol, T.any(String, Float)])
    end
    def telemetry_params(request, request_time, error)
      uri = request.dig(:params, :textDocument, :uri)

      params = {
        request: request[:method],
        lspVersion: RubyLsp::VERSION,
        requestTime: request_time,
      }

      if error
        params[:errorClass] = error.class.name
        params[:errorMessage] = error.message
      end

      params[:uri] = uri.sub(%r{.*://#{Dir.home}}, "~") if uri
      params
    end
  end
end
