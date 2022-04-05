# frozen_string_literal: true

module RubyLsp
  module Requests
    autoload :DocumentSymbol, "ruby_lsp/requests/document_symbol"
    autoload :FoldingRanges, "ruby_lsp/requests/folding_ranges"
    autoload :SemanticHighlighting, "ruby_lsp/requests/semantic_highlighting"
    autoload :Formatting, "ruby_lsp/requests/formatting"
    autoload :Diagnostics, "ruby_lsp/requests/diagnostics"
  end
end
