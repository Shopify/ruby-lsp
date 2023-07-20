# typed: strict
# frozen_string_literal: true

module RubyLsp
  # Listener is an abstract class to be used by requests for listening to events emitted when visiting an AST using the
  # EventEmitter.
  class Listener
    extend T::Sig
    extend T::Helpers
    extend T::Generic
    include Requests::Support::Common

    ResponseType = type_member

    abstract!

    sig { params(emitter: EventEmitter, message_queue: Thread::Queue).void }
    def initialize(emitter, message_queue)
      @emitter = emitter
      @message_queue = message_queue
      @external_listeners = T.let([], T::Array[RubyLsp::Listener[ResponseType]])
    end

    # Override this method with an attr_reader that returns the response of your listener. The listener should
    # accumulate results in a @response variable and then provide the reader so that it is accessible
    sig { abstract.returns(ResponseType) }
    def response; end

    # Merge responses from all external listeners into the base listener's response. We do this to return a single
    # response to the editor including the results of all extensions
    sig { void }
    def merge_external_listeners_responses!
      @external_listeners.each { |l| merge_response!(l) }
    end

    # Does nothing by default. Requests that accept extensions should override this method to define how to merge
    # responses coming from external listeners
    sig { overridable.params(other: Listener[T.untyped]).returns(T.self_type) }
    def merge_response!(other)
      self
    end
  end
end
