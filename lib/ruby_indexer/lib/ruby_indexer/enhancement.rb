# typed: strict
# frozen_string_literal: true

module RubyIndexer
  class Enhancement
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { params(index: Index).void }
    def initialize(index)
      @index = index
    end

    # The `on_extend` indexing enhancement is invoked whenever an extend is encountered in the code. It can be used to
    # register for an included callback, similar to what `ActiveSupport::Concern` does in order to auto-extend the
    # `ClassMethods` modules
    sig do
      overridable.params(
        owner: T.nilable(Entry::Namespace),
        node: Prism::CallNode,
        file_path: String,
        code_units_cache: T.any(
          T.proc.params(arg0: Integer).returns(Integer),
          Prism::CodeUnitsCache,
        ),
      ).void
    end
    def on_call_node_enter(owner, node, file_path, code_units_cache); end

    sig do
      overridable.params(
        owner: T.nilable(Entry::Namespace),
        node: Prism::CallNode,
        file_path: String,
        code_units_cache: T.any(
          T.proc.params(arg0: Integer).returns(Integer),
          Prism::CodeUnitsCache,
        ),
      ).void
    end
    def on_call_node_leave(owner, node, file_path, code_units_cache); end
  end
end
