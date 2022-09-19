# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class SyntaxErrorDiagnostic
        extend T::Sig

        sig { params(edit: Document::EditShape).void }
        def initialize(edit)
          @edit = edit
        end

        sig { returns(FalseClass) }
        def correctable?
          false
        end

        sig { returns(LanguageServer::Protocol::Interface::Diagnostic) }
        def to_lsp_diagnostic
          LanguageServer::Protocol::Interface::Diagnostic.new(
            message: "Syntax error",
            source: "SyntaxTree",
            severity: LanguageServer::Protocol::Constant::DiagnosticSeverity::ERROR,
            range: @edit[:range],
          )
        end
      end
    end
  end
end
