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
  GUESSED_TYPES_URL = "https://shopify.github.io/ruby-lsp/design-and-roadmap.html#guessed-types"

  # Request delegation for embedded languages is not yet standardized into the language server specification. Here we
  # use this custom error class as a way to return a signal to the client that the request should be delegated to the
  # language server for the host language. The support for delegation is custom built on the client side, so each editor
  # needs to implement their own until this becomes a part of the spec
  class DelegateRequestError < StandardError
    # A custom error code that clients can use to handle delegate requests. This is past the range of error codes listed
    # by the specification to avoid conflicting with other error types
    CODE = -32900
  end

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
    end

    extend T::Sig

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def to_hash
      { method: @method, params: T.unsafe(@params).to_hash }
    end
  end

  class Request < Message
    extend T::Sig

    sig { params(id: T.any(Integer, String), method: String, params: Object).void }
    def initialize(id:, method:, params:)
      @id = id
      super(method: method, params: params)
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def to_hash
      { id: @id, method: @method, params: T.unsafe(@params).to_hash }
    end
  end

  class Error
    extend T::Sig

    sig { returns(String) }
    attr_reader :message

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
