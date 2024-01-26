# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    autoload :ResponseBuilder, "ruby_lsp/response_builders/response_builder"
    autoload :CodeLens, "ruby_lsp/response_builders/code_lens"
    autoload :DocumentSymbol, "ruby_lsp/response_builders/document_symbol"
    autoload :Hover, "ruby_lsp/response_builders/hover"
    autoload :SemanticHighlighting, "ruby_lsp/response_builders/semantic_highlighting"
  end
end
