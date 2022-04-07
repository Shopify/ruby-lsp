# frozen_string_literal: true

module RubyLsp
  module Requests
    # # Diagnostics
    #
    # [Specification doc](https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_publishDiagnostics)
    #
    # Publishes RuboCop diagnostics for the selected file.
    class Diagnostics < RuboCopRequest
      RUBOCOP_TO_LSP_SEVERITY = {
        convention: LanguageServer::Protocol::Constant::DiagnosticSeverity::INFORMATION,
        info: LanguageServer::Protocol::Constant::DiagnosticSeverity::INFORMATION,
        refactor: LanguageServer::Protocol::Constant::DiagnosticSeverity::INFORMATION,
        warning: LanguageServer::Protocol::Constant::DiagnosticSeverity::WARNING,
        error: LanguageServer::Protocol::Constant::DiagnosticSeverity::ERROR,
        fatal: LanguageServer::Protocol::Constant::DiagnosticSeverity::ERROR,
      }.freeze

      def run
        super

        @diagnostics
      end

      def file_finished(_file, offenses)
        @diagnostics = offenses.map do |offense|
          LanguageServer::Protocol::Interface::Diagnostic.new(
            message: offense.message,
            source: "RuboCop",
            code: offense.cop_name,
            severity: RUBOCOP_TO_LSP_SEVERITY[offense.severity.name],
            range: LanguageServer::Protocol::Interface::Range.new(
              start: LanguageServer::Protocol::Interface::Position.new(
                line: offense.line - 1,
                character: offense.column
              ),
              end: LanguageServer::Protocol::Interface::Position.new(
                line: offense.last_line - 1,
                character: offense.last_column
              )
            )
          )
        end
      end
    end
  end
end
