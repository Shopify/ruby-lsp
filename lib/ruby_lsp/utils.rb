# typed: strict
# frozen_string_literal: true

module RubyLsp
  # rubocop:disable RubyLsp/UseLanguageServerAliases
  Interface = LanguageServer::Protocol::Interface
  Constant = LanguageServer::Protocol::Constant
  # rubocop:enable RubyLsp/UseLanguageServerAliases

  # Used to indicate that a request shouldn't return a response
  BUNDLE_PATH = begin
    Bundler.bundle_path.to_s
  rescue Bundler::GemfileNotFound
    nil
  end #: String?
  GEMFILE_NAME = begin
    Bundler.with_original_env { Bundler.default_gemfile.basename.to_s }
  rescue Bundler::GemfileNotFound
    "Gemfile"
  end #: String
  GUESSED_TYPES_URL = "https://shopify.github.io/ruby-lsp/#guessed-types"
  TEST_PATH_PATTERN = "**/{test,spec,features}/**/{*_test.rb,test_*.rb,*_spec.rb,*.feature}"

  # Request delegation for embedded languages is not yet standardized into the language server specification. Here we
  # use this custom error class as a way to return a signal to the client that the request should be delegated to the
  # language server for the host language. The support for delegation is custom built on the client side, so each editor
  # needs to implement their own until this becomes a part of the spec
  class DelegateRequestError < StandardError
    # A custom error code that clients can use to handle delegate requests. This is past the range of error codes listed
    # by the specification to avoid conflicting with other error types
    CODE = -32900
  end

  class AbstractMethodInvokedError < StandardError; end

  BUNDLE_COMPOSE_FAILED_CODE = -33000

  # A notification to be sent to the client
  # @abstract
  class Message
    #: String
    attr_reader :method

    #: Object
    attr_reader :params

    #: (method: String, params: Object) -> void
    def initialize(method:, params:)
      @method = method
      @params = params
    end

    # @abstract
    #: -> Hash[Symbol, untyped]
    def to_hash
      raise AbstractMethodInvokedError
    end
  end

  class Notification < Message
    class << self
      #: (String message, ?type: Integer) -> Notification
      def window_show_message(message, type: Constant::MessageType::INFO)
        new(
          method: "window/showMessage",
          params: Interface::ShowMessageParams.new(type: type, message: message),
        )
      end

      #: (String message, ?type: Integer) -> Notification
      def window_log_message(message, type: Constant::MessageType::LOG)
        new(
          method: "window/logMessage",
          params: Interface::LogMessageParams.new(type: type, message: message),
        )
      end

      #: (Hash[Symbol, untyped] data) -> Notification
      def telemetry(data)
        new(
          method: "telemetry/event",
          params: data,
        )
      end

      #: (String id, String title, ?percentage: Integer?, ?message: String?) -> Notification
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

      #: (String id, ?percentage: Integer?, ?message: String?) -> Notification
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

      #: (String id) -> Notification
      def progress_end(id)
        Notification.new(
          method: "$/progress",
          params: Interface::ProgressParams.new(
            token: id,
            value: Interface::WorkDoneProgressEnd.new(kind: "end"),
          ),
        )
      end

      #: (String uri, Array[Interface::Diagnostic] diagnostics, ?version: Integer?) -> Notification
      def publish_diagnostics(uri, diagnostics, version: nil)
        new(
          method: "textDocument/publishDiagnostics",
          params: Interface::PublishDiagnosticsParams.new(uri: uri, diagnostics: diagnostics, version: version),
        )
      end
    end

    # @override
    #: -> Hash[Symbol, untyped]
    def to_hash
      hash = { method: @method }

      if @params
        hash[:params] = @params #: as untyped
          .to_hash
      end

      hash
    end
  end

  class Request < Message
    class << self
      #: (Integer id, (Interface::RelativePattern | String) pattern, ?kind: Integer, ?registration_id: String?) -> Request
      def register_watched_files(
        id,
        pattern,
        kind: Constant::WatchKind::CREATE | Constant::WatchKind::CHANGE | Constant::WatchKind::DELETE,
        registration_id: nil
      )
        new(
          id: id,
          method: "client/registerCapability",
          params: Interface::RegistrationParams.new(
            registrations: [
              Interface::Registration.new(
                id: registration_id || SecureRandom.uuid,
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

    #: (id: (Integer | String), method: String, params: Object) -> void
    def initialize(id:, method:, params:)
      @id = id
      super(method: method, params: params)
    end

    # @override
    #: -> Hash[Symbol, untyped]
    def to_hash
      hash = { id: @id, method: @method }

      if @params
        hash[:params] = @params #: as untyped
          .to_hash
      end

      hash
    end
  end

  class Error
    #: String
    attr_reader :message

    #: Integer
    attr_reader :code

    #: (id: Integer, code: Integer, message: String, ?data: Hash[Symbol, untyped]?) -> void
    def initialize(id:, code:, message:, data: nil)
      @id = id
      @code = code
      @message = message
      @data = data
    end

    #: -> Hash[Symbol, untyped]
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
    #: untyped
    attr_reader :response

    #: Integer
    attr_reader :id

    #: (id: Integer, response: untyped) -> void
    def initialize(id:, response:)
      @id = id
      @response = response
    end

    #: -> Hash[Symbol, untyped]
    def to_hash
      { id: @id, result: @response }
    end
  end

  # A request configuration, to turn on/off features
  class RequestConfig
    #: (Hash[Symbol, bool] configuration) -> void
    def initialize(configuration)
      @configuration = configuration
    end

    #: (Symbol feature) -> bool?
    def enabled?(feature)
      @configuration[:enableAll] || @configuration[feature]
    end

    #: (Hash[Symbol, bool]) -> void
    def merge!(hash)
      @configuration.merge!(hash)
    end
  end

  class SorbetLevel
    class << self
      #: -> SorbetLevel
      def ignore
        new("ignore")
      end
    end

    #: (String?) -> void
    def initialize(sigil)
      @level = case sigil
      when "ignore"
        :ignore
      when "false"
        :false
      when "true"
        :true
      when "strict", "strong"
        :strict
      else
        :none
      end #: Symbol
    end

    #: -> bool
    def ignore? = @level == :ignore

    #: -> bool
    def false? = @level == :false

    #: -> bool
    def true? = @level == :true

    #: -> bool
    def strict? = @level == :strict

    #: -> bool
    def none? = @level == :none

    #: -> bool
    def true_or_higher? = @level == :true || @level == :strict
  end

  # Reads JSON RPC messages from the given IO in a loop
  class MessageReader
    #: (IO) -> void
    def initialize(io)
      @io = io
    end

    #: () { (Hash[Symbol, untyped]) -> void } -> void
    def each_message(&block)
      while (headers = @io.gets("\r\n\r\n"))
        raw_message = @io.read(headers[/Content-Length: (\d+)/i, 1].to_i) #: as !nil
        block.call(JSON.parse(raw_message, symbolize_names: true))
      end
    end
  end

  # Writes JSON RPC messages to the given IO
  class MessageWriter
    #: (IO) -> void
    def initialize(io)
      @io = io
    end

    #: (Hash[Symbol, untyped]) -> void
    def write(message)
      message[:jsonrpc] = "2.0"
      json_message = message.to_json

      @io.write("Content-Length: #{json_message.bytesize}\r\n\r\n#{json_message}")
      @io.flush
    end
  end
end
