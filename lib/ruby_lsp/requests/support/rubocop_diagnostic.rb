# typed: true
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class RuboCopDiagnostic
        RUBOCOP_TO_LSP_SEVERITY = {
          convention: LanguageServer::Protocol::Constant::DiagnosticSeverity::INFORMATION,
          info: LanguageServer::Protocol::Constant::DiagnosticSeverity::INFORMATION,
          refactor: LanguageServer::Protocol::Constant::DiagnosticSeverity::INFORMATION,
          warning: LanguageServer::Protocol::Constant::DiagnosticSeverity::WARNING,
          error: LanguageServer::Protocol::Constant::DiagnosticSeverity::ERROR,
          fatal: LanguageServer::Protocol::Constant::DiagnosticSeverity::ERROR,
        }.freeze

        attr_reader :replacements

        def initialize(offense, uri)
          @offense = offense
          @uri = uri
          @replacements = offense.correctable? ? offense_replacements : []
        end

        def correctable?
          @offense.correctable?
        end

        def in_range?(range)
          range.cover?(@offense.line - 1)
        end

        def to_lsp_code_action
          LanguageServer::Protocol::Interface::CodeAction.new(
            title: "Autocorrect #{@offense.cop_name}",
            kind: LanguageServer::Protocol::Constant::CodeActionKind::QUICK_FIX,
            edit: LanguageServer::Protocol::Interface::WorkspaceEdit.new(
              document_changes: [
                LanguageServer::Protocol::Interface::TextDocumentEdit.new(
                  text_document: LanguageServer::Protocol::Interface::OptionalVersionedTextDocumentIdentifier.new(
                    uri: @uri,
                    version: nil
                  ),
                  edits: @replacements
                ),
              ]
            ),
            is_preferred: true,
          )
        end

        def to_lsp_diagnostic
          LanguageServer::Protocol::Interface::Diagnostic.new(
            message: @offense.message,
            source: "RuboCop",
            code: @offense.cop_name,
            severity: RUBOCOP_TO_LSP_SEVERITY[@offense.severity.name],
            range: LanguageServer::Protocol::Interface::Range.new(
              start: LanguageServer::Protocol::Interface::Position.new(
                line: @offense.line - 1,
                character: @offense.column
              ),
              end: LanguageServer::Protocol::Interface::Position.new(
                line: @offense.last_line - 1,
                character: @offense.last_column
              )
            )
          )
        end

        private

        def offense_replacements
          @offense.corrector.as_replacements.map do |range, replacement|
            LanguageServer::Protocol::Interface::TextEdit.new(
              range: LanguageServer::Protocol::Interface::Range.new(
                start: LanguageServer::Protocol::Interface::Position.new(line: range.line - 1, character: range.column),
                end: LanguageServer::Protocol::Interface::Position.new(line: range.last_line - 1,
                  character: range.last_column)
              ),
              new_text: replacement
            )
          end
        end
      end
    end
  end
end
