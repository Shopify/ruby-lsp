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
    end

    class << self
      extend T::Sig

      sig { returns(T::Array[T.class_of(Listener)]) }
      def listeners
        @listeners ||= T.let([], T.nilable(T::Array[T.class_of(Listener)]))
      end

      sig { params(listener: T.class_of(Listener)).void }
      def add_listener(listener)
        listeners << listener
      end
    end

    # Override this method with an attr_reader that returns the response of your listener. The listener should
    # accumulate results in a @response variable and then provide the reader so that it is accessible
    sig { abstract.returns(ResponseType) }
    def response; end
  end
end
