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
      sig { params(message: String).returns(Notification) }
      def window_show_error(message)
        new(
          method: "window/showMessage",
          params: Interface::ShowMessageParams.new(
            type: Constant::MessageType::ERROR,
            message: message,
          ),
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
