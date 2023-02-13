# typed: strict

module SyntaxTree
  module WithScope
    sig { returns(Scope)}
    def current_scope; end

    class Scope
      sig { params(name: String).returns(T.nilable(Local)) }
      def find_local(name); end
    end
  end
end
