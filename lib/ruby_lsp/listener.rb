# typed: strict
# frozen_string_literal: true

module RubyLsp
  # Listener is an abstract class to be used by requests for listening to events emitted when visiting an AST using the
  # EventEmitter.
  class Listener
    extend T::Sig
    extend T::Helpers
    include Requests::Support::Common

    abstract!

    # Override this method with an attr_reader that returns the response of your listener. The listener should
    # accumulate results in a @response variable and then provide the reader so that it is accessible
    sig { abstract.returns(Object) }
    def response; end

    sig { overridable.params(node: SyntaxTree::Command).void }
    def on_command(node); end

    sig { overridable.params(node: SyntaxTree::CallNode).void }
    def on_call(node); end

    sig { overridable.params(node: SyntaxTree::ConstPathRef).void }
    def on_const_path_ref(node); end
  end
end
