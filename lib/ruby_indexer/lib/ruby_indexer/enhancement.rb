# typed: strict
# frozen_string_literal: true

module RubyIndexer
  module Enhancement
    extend T::Sig
    extend T::Helpers

    interface!

    requires_ancestor { Object }

    # The `on_extend` indexing enhancement is invoked whenever an extend is encountered in the code. It can be used to
    # register for an included callback, similar to what `ActiveSupport::Concern` does in order to auto-extend the
    # `ClassMethods` modules
    sig do
      abstract.params(
        index: Index,
        owner: T.nilable(Entry::Namespace),
        node: Prism::CallNode,
        file_path: String,
      ).void
    end
    def on_call_node(index, owner, node, file_path); end
  end
end
