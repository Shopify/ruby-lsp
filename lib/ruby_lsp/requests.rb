# typed: strict
# frozen_string_literal: true

module RubyLsp
  # Supported features
  #
  # - [DocumentSymbol](rdoc-ref:RubyLsp::Requests::DocumentSymbol)
  # - [DocumentLink](rdoc-ref:RubyLsp::Requests::DocumentLink)
  # - [Hover](rdoc-ref:RubyLsp::Requests::Hover)
  # - [FoldingRange](rdoc-ref:RubyLsp::Requests::FoldingRanges)
  # - [SelectionRange](rdoc-ref:RubyLsp::Requests::SelectionRanges)
  # - [SemanticHighlighting](rdoc-ref:RubyLsp::Requests::SemanticHighlighting)
  # - [Formatting](rdoc-ref:RubyLsp::Requests::Formatting)
  # - [OnTypeFormatting](rdoc-ref:RubyLsp::Requests::OnTypeFormatting)
  # - [Diagnostic](rdoc-ref:RubyLsp::Requests::Diagnostics)
  # - [CodeAction](rdoc-ref:RubyLsp::Requests::CodeActions)
  # - [CodeActionResolve](rdoc-ref:RubyLsp::Requests::CodeActionResolve)
  # - [DocumentHighlight](rdoc-ref:RubyLsp::Requests::DocumentHighlight)
  # - [InlayHint](rdoc-ref:RubyLsp::Requests::InlayHints)
  # - [Completion](rdoc-ref:RubyLsp::Requests::Completion)
  # - [CompletionResolve](rdoc-ref:RubyLsp::Requests::CompletionResolve)
  # - [CodeLens](rdoc-ref:RubyLsp::Requests::CodeLens)
  # - [Definition](rdoc-ref:RubyLsp::Requests::Definition)
  # - [ShowSyntaxTree](rdoc-ref:RubyLsp::Requests::ShowSyntaxTree)
  # - [WorkspaceSymbol](rdoc-ref:RubyLsp::Requests::WorkspaceSymbol)
  # - [SignatureHelp](rdoc-ref:RubyLsp::Requests::SignatureHelp)

  module Requests
    autoload :Request, "ruby_lsp/requests/request"
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
    autoload :CodeActionResolve, "ruby_lsp/requests/code_action_resolve"
    autoload :DocumentHighlight, "ruby_lsp/requests/document_highlight"
    autoload :InlayHints, "ruby_lsp/requests/inlay_hints"
    autoload :Completion, "ruby_lsp/requests/completion"
    autoload :CompletionResolve, "ruby_lsp/requests/completion_resolve"
    autoload :CodeLens, "ruby_lsp/requests/code_lens"
    autoload :Definition, "ruby_lsp/requests/definition"
    autoload :ShowSyntaxTree, "ruby_lsp/requests/show_syntax_tree"
    autoload :WorkspaceSymbol, "ruby_lsp/requests/workspace_symbol"
    autoload :SignatureHelp, "ruby_lsp/requests/signature_help"
    autoload :PrepareTypeHierarchy, "ruby_lsp/requests/prepare_type_hierarchy"
    autoload :TypeHierarchySupertypes, "ruby_lsp/requests/type_hierarchy_supertypes"

    # :nodoc:
    module Support
      autoload :RuboCopDiagnostic, "ruby_lsp/requests/support/rubocop_diagnostic"
      autoload :SelectionRange, "ruby_lsp/requests/support/selection_range"
      autoload :Annotation, "ruby_lsp/requests/support/annotation"
      autoload :Sorbet, "ruby_lsp/requests/support/sorbet"
      autoload :RailsDocumentClient, "ruby_lsp/requests/support/rails_document_client"
      autoload :Common, "ruby_lsp/requests/support/common"
      autoload :Formatter, "ruby_lsp/requests/support/formatter"
    end
  end
end
