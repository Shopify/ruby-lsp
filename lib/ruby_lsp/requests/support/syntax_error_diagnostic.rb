# typed: true
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class SyntaxErrorDiagnostic
        def initialize(edit)
          @edit = edit
        end

        def correctable?
          false
        end

        def to_lsp_diagnostic
          LanguageServer::Protocol::Interface::Diagnostic.new(
            message: "Syntax error",
            source: "SyntaxTree",
            severity: LanguageServer::Protocol::Constant::DiagnosticSeverity::ERROR,
            range: @edit[:range]
          )
        end
      end
    end
  end
end
