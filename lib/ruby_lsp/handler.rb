# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests"
require "ruby_lsp/store"
require "benchmark"

module RubyLsp
  Interface = LanguageServer::Protocol::Interface
  Constant = LanguageServer::Protocol::Constant
  Transport = LanguageServer::Protocol::Transport

  class Handler
    extend T::Sig
    VOID = T.let(Object.new.freeze, Object)

    sig { params(blk: T.proc.bind(Handler).params(arg0: T.untyped).void).void }
    def self.start(&blk)
      handler = new
      handler.instance_exec(&blk)
      handler.start
    end

    sig { returns(Store) }
    attr_reader :store

    sig { void }
    def initialize
      @writer = T.let(Transport::Stdio::Writer.new, Transport::Stdio::Writer)
      @reader = T.let(Transport::Stdio::Reader.new, Transport::Stdio::Reader)
      @handlers = T.let({}, T::Hash[String, T.proc.params(request: T::Hash[Symbol, T.untyped]).returns(T.untyped)])
      @store = T.let(Store.new, Store)
    end

    sig { void }
    def start
      $stderr.puts "Starting Ruby LSP..."
      @reader.read { |request| handle(request) }
    end

    private

    sig do
      params(
        msg: String,
        blk: T.proc.bind(Handler).params(request: T::Hash[Symbol, T.untyped]).returns(T.untyped)
      ).void
    end
    def on(msg, &blk)
      @handlers[msg] = blk
    end

    sig { params(request: T::Hash[Symbol, T.untyped]).void }
    def handle(request)
      result = T.let(nil, T.untyped)
      error = T.let(nil, T.nilable(StandardError))
      handler = @handlers[request[:method]]

      request_time = Benchmark.realtime do
        if handler
          begin
            result = handler.call(request)
          rescue StandardError => e
            error = e
          end

          if error
            @writer.write(
              {
                id: request[:id],
                error: { code: Constant::ErrorCodes::INTERNAL_ERROR, message: error.inspect, data: request.to_json },
              }
            )
          elsif result != VOID
            @writer.write(id: request[:id], result: result)
          end
        end
      end

      @writer.write(method: "telemetry/event", params: telemetry_params(request, request_time, error))
    end

    sig { void }
    def shutdown
      $stderr.puts "Shutting down Ruby LSP..."
      store.clear
    end

    sig { params(uri: String).void }
    def send_diagnostics(uri)
      response = store.cache_fetch(uri, :diagnostics) do |document|
        Requests::Diagnostics.new(uri, document).run
      end

      @writer.write(
        method: "textDocument/publishDiagnostics",
        params: Interface::PublishDiagnosticsParams.new(
          uri: uri,
          diagnostics: response.map(&:to_lsp_diagnostic)
        )
      )
    rescue RuboCop::ValidationError => e
      show_message(Constant::MessageType::ERROR, "Error in RuboCop configuration file: #{e.message}")
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
