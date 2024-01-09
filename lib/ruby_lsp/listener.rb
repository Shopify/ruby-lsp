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
      super()
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
end
