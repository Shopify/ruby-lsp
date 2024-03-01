# typed: strict
# frozen_string_literal: true

module RubyLsp
  # Used to indicate that a request shouldn't return a response
  VOID = T.let(Object.new.freeze, Object)
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

    abstract!

    sig { returns(String) }
    attr_reader :message

    sig { returns(Object) }
    attr_reader :params

    sig { params(message: String, params: Object).void }
    def initialize(message:, params:)
      @message = message
      @params = params
    end
  end

  class Notification < Message
    class << self
      extend T::Sig
      sig { params(message: String).returns(Notification) }
      def window_show_error(message)
        new(
          message: "window/showMessage",
          params: Interface::ShowMessageParams.new(
            type: Constant::MessageType::ERROR,
            message: message,
          ),
        )
      end
    end
  end

  class Request < Message; end

  # The final result of running a request before its IO is finalized
  class Result
    extend T::Sig

    sig { returns(T.untyped) }
    attr_reader :response

    sig { returns(T.nilable(Exception)) }
    attr_reader :error

    sig { params(response: T.untyped, error: T.nilable(Exception)).void }
    def initialize(response:, error: nil)
      @response = response
      @error = error
    end
  end

  # A request that will sit in the queue until it's executed
  class Job
    extend T::Sig

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :request

    sig { returns(T::Boolean) }
    attr_reader :cancelled

    sig { params(request: T::Hash[Symbol, T.untyped], cancelled: T::Boolean).void }
    def initialize(request:, cancelled:)
      @request = request
      @cancelled = cancelled
    end

    sig { void }
    def cancel
      @cancelled = true
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
