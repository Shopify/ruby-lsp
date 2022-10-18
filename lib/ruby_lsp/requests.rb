# typed: strict
# frozen_string_literal: true

module RubyLsp
  # Supported features
  #
  # - {RubyLsp::Requests::DocumentSymbol}
  # - {RubyLsp::Requests::DocumentLink}
  # - {RubyLsp::Requests::Hover}
  # - {RubyLsp::Requests::FoldingRanges}
  # - {RubyLsp::Requests::SelectionRanges}
  # - {RubyLsp::Requests::SemanticHighlighting}
  # - {RubyLsp::Requests::Formatting}
  # - {RubyLsp::Requests::OnTypeFormatting}
  # - {RubyLsp::Requests::Diagnostics}
  # - {RubyLsp::Requests::CodeActions}
  # - {RubyLsp::Requests::DocumentHighlight}
  # - {RubyLsp::Requests::InlayHints}

  module Requests
    autoload :BaseRequest, "ruby_lsp/requests/base_request"
    autoload :DocumentSymbol, "ruby_lsp/requests/document_symbol"
    autoload :DocumentLink, "ruby_lsp/requests/document_link"
    autoload :Hover, "ruby_lsp/requests/hover"
    autoload :FoldingRanges, "ruby_lsp/requests/folding_ranges"
    autoload :SelectionRanges, "ruby_lsp/requests/selection_ranges"
    autoload :SemanticHighlighting, "ruby_lsp/requests/semantic_highlighting"
    autoload :Formatting, "ruby_lsp/requests/formatting"
    autoload :OnTypeFormatting, "ruby_lsp/requests/on_type_formatting"
    autoload :Diagnostics, "ruby_lsp/requests/diagnostics"
    autoload :CodeActions, "ruby_lsp/requests/code_actions"
    autoload :DocumentHighlight, "ruby_lsp/requests/document_highlight"
    autoload :InlayHints, "ruby_lsp/requests/inlay_hints"

    # :nodoc:
    module Support
      autoload :RuboCopDiagnostic, "ruby_lsp/requests/support/rubocop_diagnostic"
      autoload :SelectionRange, "ruby_lsp/requests/support/selection_range"
      autoload :SemanticTokenEncoder, "ruby_lsp/requests/support/semantic_token_encoder"
      autoload :SyntaxErrorDiagnostic, "ruby_lsp/requests/support/syntax_error_diagnostic"
      autoload :HighlightTarget, "ruby_lsp/requests/support/highlight_target"
      autoload :RailsDocumentClient, "ruby_lsp/requests/support/rails_document_client"
    end
  end
end
