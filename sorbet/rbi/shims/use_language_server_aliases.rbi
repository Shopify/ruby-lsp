# typed: true

class RuboCop::Cop::RubyLsp::UseLanguageServerAliases
  sig { void }
  def on_new_investigation; end

  sig { params(ast: T.untyped).returns(T.untyped) }
  def ruby_lsp_modules(ast); end

  sig { params(node: T.untyped).returns(T.untyped) }
  def lsp_constant_usages(node); end
end
