# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Listener
    extend T::Sig
    extend T::Helpers
    include Requests::Support::Common

    abstract!

    sig { overridable.params(node: SyntaxTree::Command).void }
    def on_command(node); end

    sig { overridable.params(node: SyntaxTree::CallNode).void }
    def on_call(node); end

    sig { overridable.params(node: SyntaxTree::ConstPathRef).void }
    def on_const_path_ref(node); end
  end
end
