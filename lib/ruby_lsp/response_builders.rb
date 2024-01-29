# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    autoload :ResponseBuilder, "ruby_lsp/response_builders/response_builder"
    autoload :CodeLens, "ruby_lsp/response_builders/code_lens"
    autoload :Completion, "ruby_lsp/response_builders/completion"
    autoload :Definition, "ruby_lsp/response_builders/definition"
    autoload :DocumentHighlight, "ruby_lsp/response_builders/document_highlight"
    autoload :DocumentLink, "ruby_lsp/response_builders/document_link"
    autoload :DocumentSymbol, "ruby_lsp/response_builders/document_symbol"
    autoload :FoldingRanges, "ruby_lsp/response_builders/folding_ranges"
    autoload :Hover, "ruby_lsp/response_builders/hover"
    autoload :InlayHints, "ruby_lsp/response_builders/inlay_hints"
    autoload :SemanticHighlighting, "ruby_lsp/response_builders/semantic_highlighting"
    autoload :SignatureHelp, "ruby_lsp/response_builders/signature_help"
  end
end
