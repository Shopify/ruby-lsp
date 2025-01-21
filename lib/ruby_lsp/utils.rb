# typed: strict
# frozen_string_literal: true

module RubyLsp
  # rubocop:disable RubyLsp/UseLanguageServerAliases
  Interface = LanguageServer::Protocol::Interface
  Constant = LanguageServer::Protocol::Constant
  Transport = LanguageServer::Protocol::Transport
  # rubocop:enable RubyLsp/UseLanguageServerAliases

  # Used to indicate that a request shouldn't return a response
  BUNDLE_PATH = T.let(
    begin
      Bundler.bundle_path.to_s
    rescue Bundler::GemfileNotFound
      nil
    end,
    T.nilable(String),
  )
  GEMFILE_NAME = T.let(
    begin
      Bundler.with_original_env { Bundler.default_gemfile.basename.to_s }
    rescue Bundler::GemfileNotFound
      "Gemfile"
    end,
    String,
  )
  GUESSED_TYPES_URL = "https://shopify.github.io/ruby-lsp/#guessed-types"

  # Request delegation for embedded languages is not yet standardized into the language server specification. Here we
  # use this custom error class as a way to return a signal to the client that the request should be delegated to the
  # language server for the host language. The support for delegation is custom built on the client side, so each editor
  # needs to implement their own until this becomes a part of the spec
  class DelegateRequestError < StandardError
    # A custom error code that clients can use to handle delegate requests. This is past the range of error codes listed
    # by the specification to avoid conflicting with other error types
    CODE = -32900
  end

  BUNDLE_COMPOSE_FAILED_CODE = -33000

  # A notification to be sent to the client
  class Message
    extend T::Sig
    extend T::Helpers

    sig { returns(String) }
    attr_reader :method

    sig { returns(Object) }
    attr_reader :params

    abstract!

    sig { params(method: String, params: Object).void }
    def initialize(method:, params:)
      @method = method
      @params = params
    end

    sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
    def to_hash; end
  end

  class Notification < Message
    class << self
      extend T::Sig

      sig { params(message: String, type: Integer).returns(Notification) }
      def window_show_message(message, type: Constant::MessageType::INFO)
        new(
          method: "window/showMessage",
          params: Interface::ShowMessageParams.new(type: type, message: message),
        )
      end

      sig { params(message: String, type: Integer).returns(Notification) }
      def window_log_message(message, type: Constant::MessageType::LOG)
        new(
          method: "window/logMessage",
          params: Interface::LogMessageParams.new(type: type, message: message),
        )
      end

      sig { params(data: T::Hash[Symbol, T.untyped]).returns(Notification) }
      def telemetry(data)
        new(
          method: "telemetry/event",
          params: data,
        )
      end

      sig do
        params(
          id: String,
          title: String,
          percentage: T.nilable(Integer),
          message: T.nilable(String),
        ).returns(Notification)
      end
      def progress_begin(id, title, percentage: nil, message: nil)
        new(
          method: "$/progress",
          params: Interface::ProgressParams.new(
            token: id,
            value: Interface::WorkDoneProgressBegin.new(
              kind: "begin",
              title: title,
              percentage: percentage,
              message: message,
            ),
          ),
        )
      end

      sig do
        params(
          id: String,
          percentage: T.nilable(Integer),
          message: T.nilable(String),
        ).returns(Notification)
      end
      def progress_report(id, percentage: nil, message: nil)
        new(
          method: "$/progress",
          params: Interface::ProgressParams.new(
            token: id,
            value: Interface::WorkDoneProgressReport.new(
              kind: "report",
              percentage: percentage,
              message: message,
            ),
          ),
        )
      end

      sig { params(id: String).returns(Notification) }
      def progress_end(id)
        Notification.new(
          method: "$/progress",
          params: Interface::ProgressParams.new(
            token: id,
            value: Interface::WorkDoneProgressEnd.new(kind: "end"),
          ),
        )
      end

      sig do
        params(
          uri: String,
          diagnostics: T::Array[Interface::Diagnostic],
          version: T.nilable(Integer),
        ).returns(Notification)
      end
      def publish_diagnostics(uri, diagnostics, version: nil)
        new(
          method: "textDocument/publishDiagnostics",
          params: Interface::PublishDiagnosticsParams.new(uri: uri, diagnostics: diagnostics, version: version),
        )
      end
    end

    extend T::Sig

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def to_hash
      hash = { method: @method }
      hash[:params] = T.unsafe(@params).to_hash if @params
      hash
    end
  end

  class Request < Message
    extend T::Sig

    class << self
      extend T::Sig

      sig { params(id: Integer, pattern: T.any(Interface::RelativePattern, String), kind: Integer).returns(Request) }
      def register_watched_files(
        id,
        pattern,
        kind: Constant::WatchKind::CREATE | Constant::WatchKind::CHANGE | Constant::WatchKind::DELETE
      )
        new(
          id: id,
          method: "client/registerCapability",
          params: Interface::RegistrationParams.new(
            registrations: [
              Interface::Registration.new(
                id: "workspace/didChangeWatchedFiles",
                method: "workspace/didChangeWatchedFiles",
                register_options: Interface::DidChangeWatchedFilesRegistrationOptions.new(
                  watchers: [
                    Interface::FileSystemWatcher.new(glob_pattern: pattern, kind: kind),
                  ],
                ),
              ),
            ],
          ),
        )
      end
    end

    sig { params(id: T.any(Integer, String), method: String, params: Object).void }
    def initialize(id:, method:, params:)
      @id = id
      super(method: method, params: params)
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def to_hash
      hash = { id: @id, method: @method }
      hash[:params] = T.unsafe(@params).to_hash if @params
      hash
    end
  end

  class Error
    extend T::Sig

    sig { returns(String) }
    attr_reader :message

    sig { returns(Integer) }
    attr_reader :code

    sig { params(id: Integer, code: Integer, message: String, data: T.nilable(T::Hash[Symbol, T.untyped])).void }
    def initialize(id:, code:, message:, data: nil)
      @id = id
      @code = code
      @message = message
      @data = data
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_hash
      {
        id: @id,
        error: {
          code: @code,
          message: @message,
          data: @data,
        },
      }
    end
  end

  # The final result of running a request before its IO is finalized
  class Result
    extend T::Sig

    sig { returns(T.untyped) }
    attr_reader :response

    sig { returns(Integer) }
    attr_reader :id

    sig { params(id: Integer, response: T.untyped).void }
    def initialize(id:, response:)
      @id = id
      @response = response
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_hash
      { id: @id, result: @response }
    end
  end

  # A request configuration, to turn on/off features
  class RequestConfig
    extend T::Sig

    sig { returns(T::Hash[Symbol, T::Boolean]) }
    attr_accessor :configuration

    sig { params(configuration: T::Hash[Symbol, T::Boolean]).void }
    def initialize(configuration)
      @configuration = configuration
    end

    sig { params(feature: Symbol).returns(T.nilable(T::Boolean)) }
    def enabled?(feature)
      @configuration[:enableAll] || @configuration[feature]
    end
  end
end
