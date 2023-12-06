# typed: strict
# frozen_string_literal: true

module RubyLsp
  # Listener is an abstract class to be used by requests for listening to events emitted when visiting an AST using the
  # Prism::Dispatcher.
  class Listener
    extend T::Sig
    extend T::Helpers
    extend T::Generic
    include Requests::Support::Common

    ResponseType = type_member

    abstract!

    sig { params(dispatcher: Prism::Dispatcher).void }
    def initialize(dispatcher)
      @dispatcher = dispatcher
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

  # ExtensibleListener is an abstract class to be used by requests that accept addons.
  class ExtensibleListener < Listener
    extend T::Sig
    extend T::Generic

    ResponseType = type_member

    abstract!

    # When inheriting from ExtensibleListener, the `super` of constructor must be called **after** the subclass's own
    # ivars have been initialized. This is because the constructor of ExtensibleListener calls
    # `initialize_external_listener` which may depend on the subclass's ivars.
    sig { params(dispatcher: Prism::Dispatcher).void }
    def initialize(dispatcher)
      super
      @response_merged = T.let(false, T::Boolean)
      @external_listeners = T.let(
        Addon.addons.filter_map do |ext|
          initialize_external_listener(ext)
        end,
        T::Array[RubyLsp::Listener[ResponseType]],
      )
    end

    # Merge responses from all external listeners into the base listener's response. We do this to return a single
    # response to the editor including the results of all addons
    sig { void }
    def merge_external_listeners_responses!
      @external_listeners.each { |l| merge_response!(l) }
    end

    sig { returns(ResponseType) }
    def response
      merge_external_listeners_responses! unless @response_merged
      super
    end

    sig do
      abstract.params(addon: RubyLsp::Addon).returns(T.nilable(RubyLsp::Listener[ResponseType]))
    end
    def initialize_external_listener(addon); end

    # Does nothing by default. Requests that accept addons should override this method to define how to merge responses
    # coming from external listeners
    sig { abstract.params(other: Listener[T.untyped]).returns(T.self_type) }
    def merge_response!(other)
    end
  end
  private_constant(:ExtensibleListener)
end
