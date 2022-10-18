# typed: strict

module SyntaxTree
  module WithEnvironment
    sig { returns(Environment)}
    def current_environment; end
  end

  class Environment
    sig { params(name: String).returns(Local) }
    def find_local(name); end
  end
end
