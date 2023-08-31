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

    # Override this method with an attr_reader that returns the response of your listener. The listener should
    # accumulate results in a @response variable and then provide the reader so that it is accessible
    sig { abstract.returns(ResponseType) }
    def response; end

    module Extensible
      extend T::Sig
      extend T::Generic

      ResponseType = type_member

      abstract!

      requires_ancestor { Listener }

      sig { params(emitter: EventEmitter, message_queue: Thread::Queue).void }
      def initialize(emitter, message_queue)
        super
        @external_listeners = T.let(
          Extension.extensions.filter_map do |ext|
            initialize_external_listener(ext)
          end,
          T::Array[RubyLsp::Listener[ResponseType]],
        )
      end

      # Merge responses from all external listeners into the base listener's response. We do this to return a single
      # response to the editor including the results of all extensions
      sig { void }
      def merge_external_listeners_responses!
        @external_listeners.each { |l| merge_response!(l) }
      end

      sig do
        abstract.params(extension: RubyLsp::Extension).returns(T.nilable(RubyLsp::Listener[ResponseType]))
      end
      def initialize_external_listener(extension); end

      # Does nothing by default. Requests that accept extensions should override this method to define how to merge
      # responses coming from external listeners
      sig { abstract.params(other: Listener[T.untyped]).returns(T.self_type) }
      def merge_response!(other)
      end
    end
  end
end
