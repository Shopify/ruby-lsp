# typed: strict

module SyntaxTree::WithScope
  sig { returns(Scope)}
  def current_scope; end

  class Scope
    sig { params(name: String).returns(T.nilable(Local)) }
    def find_local(name); end
  end
end
