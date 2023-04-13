# typed: strict
# frozen_string_literal: true

module RubyLsp
  # Used to indicate that a request shouldn't return a response
  VOID = T.let(Object.new.freeze, Object)

  # This freeze is not redundant since the interpolated string is mutable
  WORKSPACE_URI = T.let("file://#{Dir.pwd}".freeze, String) # rubocop:disable Style/RedundantFreeze

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

    sig { returns(T::Array[Message]) }
    attr_reader :messages

    sig { returns(T.nilable(Exception)) }
    attr_reader :error

    sig { returns(T.nilable(Float)) }
    attr_reader :request_time

    sig do
      params(
        response: T.untyped,
        messages: T::Array[Message],
        error: T.nilable(Exception),
        request_time: T.nilable(Float),
      ).void
    end
    def initialize(response:, messages:, error: nil, request_time: nil)
      @response = response
      @messages = messages
      @error = error
      @request_time = request_time
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
