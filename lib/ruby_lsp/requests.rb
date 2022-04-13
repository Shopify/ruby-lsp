# frozen_string_literal: true

module RubyLsp
  module Requests
    autoload :BaseRequest, "ruby_lsp/requests/base_request"
    autoload :DocumentSymbol, "ruby_lsp/requests/document_symbol"
    autoload :FoldingRanges, "ruby_lsp/requests/folding_ranges"
    autoload :SemanticHighlighting, "ruby_lsp/requests/semantic_highlighting"
    autoload :RuboCopRequest, "ruby_lsp/requests/rubocop_request"
    autoload :Formatting, "ruby_lsp/requests/formatting"
    autoload :Diagnostics, "ruby_lsp/requests/diagnostics"
    autoload :CodeActions, "ruby_lsp/requests/code_actions"
  end
end
