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

    sig { returns(ResponseType) }
    def response
      _response
    end

    # Override this method with an attr_reader that returns the response of your listener. The listener should
    # accumulate results in a @response variable and then provide the reader so that it is accessible
    sig { abstract.returns(ResponseType) }
    def _response; end
  end
  private_constant(:Listener)

  # ExtensibleListener is an abstract class to be used by requests that accept extensions.
  class ExtensibleListener < Listener
    extend T::Sig
    extend T::Generic

    ResponseType = type_member

    abstract!

    # When inheriting from ExtensibleListener, the `super` of constructor must be called **after** the subclass's own
    # ivars have been initialized. This is because the constructor of ExtensibleListener calls
    # `initialize_external_listener` which may depend on the subclass's ivars.
    sig { params(emitter: EventEmitter, message_queue: Thread::Queue).void }
    def initialize(emitter, message_queue)
      super
      @response_merged = T.let(false, T::Boolean)
      @external_listeners = T.let(
        Extension.extensions.filter_map do |ext|
          initialize_external_listener(ext)
        end,
        T::Array[RubyLsp::ExtensionListener[ResponseType]],
      )
    end

    # Merge responses from all external listeners into the base listener's response. We do this to return a single
    # response to the editor including the results of all extensions
    sig { void }
    def merge_external_listeners_responses!
      @external_listeners.each { |l| l.merge_response(_response) }
    end

    sig { returns(ResponseType) }
    def response
      merge_external_listeners_responses! unless @response_merged
      super
    end

    sig do
      abstract.params(extension: RubyLsp::Extension).returns(T.nilable(RubyLsp::ExtensionListener[ResponseType]))
    end
    def initialize_external_listener(extension); end
  end
  private_constant(:ExtensibleListener)

  class ExtensionListener < Listener
    extend T::Sig
    extend T::Helpers
    extend T::Generic

    ResponseType = type_member

    abstract!

    sig { abstract.params(current_response: ResponseType).void }
    def merge_response(current_response); end
  end
end
