# typed: true

class RuboCop::Cop::RubyLsp::UseRegisterWithHandlerMethod
  sig { void }
  def on_new_investigation; end

  sig { params(ast: T.untyped).returns(T::Array[RuboCop::AST::SymbolNode]) }
  def find_all_listeners(ast); end

  sig { params(ast: T.untyped).returns(T::Array[RuboCop::AST::DefNode]) }
  def find_all_handlers(ast); end
end
