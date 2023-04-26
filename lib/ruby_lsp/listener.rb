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

    sig { params(uri: String, message_queue: Thread::Queue).void }
    def initialize(uri, message_queue)
      @message_queue = message_queue
      @uri = uri
    end

    @event_to_listener_map = T.let(Hash.new { |h, k| h[k] = [] }, T::Hash[Symbol, T::Array[T.class_of(Listener)]])

    sig { params(event: Symbol).returns(T.nilable(T::Boolean)) }
    def registered_for_event?(event)
      Listener.event_to_listener_map[event]&.include?(self.class)
    end

    class << self
      extend T::Sig

      sig { returns(T::Hash[Symbol, T::Array[T.class_of(Listener)]]) }
      attr_reader :event_to_listener_map

      sig { returns(T::Array[T.class_of(Listener)]) }
      def listeners
        @listeners ||= T.let([], T.nilable(T::Array[T.class_of(Listener)]))
      end

      sig { params(listener: T.class_of(Listener)).void }
      def add_listener(listener)
        listeners << listener
      end

      # All listener events must be defined inside of a `listener_events` block. This is to ensure we know which events
      # have been registered. Defining an event outside of this block will simply not register it and it'll never be
      # invoked
      sig { params(block: T.proc.void).void }
      def listener_events(&block)
        current_methods = instance_methods
        block.call

        (instance_methods - current_methods).each do |event|
          T.must(Listener.event_to_listener_map[event]) << self
        end
      end
    end

    # Override this method with an attr_reader that returns the response of your listener. The listener should
    # accumulate results in a @response variable and then provide the reader so that it is accessible
    sig { abstract.returns(ResponseType) }
    def response; end
  end
end
