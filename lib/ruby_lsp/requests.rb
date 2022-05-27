# frozen_string_literal: true

module RubyLsp
  module Requests
    autoload :BaseRequest, "ruby_lsp/requests/base_request"
    autoload :DocumentSymbol, "ruby_lsp/requests/document_symbol"
    autoload :FoldingRanges, "ruby_lsp/requests/folding_ranges"
    autoload :SelectionRanges, "ruby_lsp/requests/selection_ranges"
    autoload :SemanticHighlighting, "ruby_lsp/requests/semantic_highlighting"
    autoload :Formatting, "ruby_lsp/requests/formatting"
    autoload :Diagnostics, "ruby_lsp/requests/diagnostics"
    autoload :CodeActions, "ruby_lsp/requests/code_actions"

    module Support
      autoload :RuboCopDiagnostic, "ruby_lsp/requests/support/rubocop_diagnostic"
      autoload :RuboCopRunner, "ruby_lsp/requests/support/rubocop_runner"
      autoload :SelectionRange, "ruby_lsp/requests/support/selection_range"
      autoload :SyntaxErrorDiagnostic, "ruby_lsp/requests/support/syntax_error_diagnostic"
    end

    module Middleware
      autoload :RuboCop, "ruby_lsp/requests/middleware/rubocop"
      autoload :SyntaxError, "ruby_lsp/requests/middleware/syntax_error"
    end
  end
end
