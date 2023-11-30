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

  class Notification < Message; end
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
end
