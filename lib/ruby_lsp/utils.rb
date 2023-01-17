# typed: strict
# frozen_string_literal: true

module RubyLsp
  # Used to indicate that a request shouldn't return a response
  VOID = T.let(Object.new.freeze, Object)

  # A notification to be sent to the client
  class Notification < T::Struct
    const :message, String
    const :params, Object
  end

  # The final result of running a request before its IO is finalized
  class Result < T::Struct
    const :response, T.untyped # rubocop:disable Sorbet/ForbidUntypedStructProps
    const :error, T.nilable(Exception)
    const :request_time, T.nilable(Float)
    const :notifications, T::Array[Notification]
  end

  # A request that will sit in the queue until it's executed
  class Job < T::Struct
    extend T::Sig

    const :request, T::Hash[Symbol, T.untyped]
    prop :cancelled, T::Boolean

    sig { void }
    def cancel
      self.cancelled = true
    end
  end
end
