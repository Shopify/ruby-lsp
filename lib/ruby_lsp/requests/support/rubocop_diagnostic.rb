# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class RuboCopDiagnostic
        extend T::Sig

        RUBOCOP_TO_LSP_SEVERITY = T.let(
          {
            convention: Constant::DiagnosticSeverity::INFORMATION,
            info: Constant::DiagnosticSeverity::INFORMATION,
            refactor: Constant::DiagnosticSeverity::INFORMATION,
            warning: Constant::DiagnosticSeverity::WARNING,
            error: Constant::DiagnosticSeverity::ERROR,
            fatal: Constant::DiagnosticSeverity::ERROR,
          }.freeze,
          T::Hash[Symbol, Integer],
        )

        sig { params(offense: RuboCop::Cop::Offense, uri: String).void }
        def initialize(offense, uri)
          @offense = offense
          @uri = uri
        end

        sig { returns(Interface::CodeAction) }
        def to_lsp_code_action
          Interface::CodeAction.new(
            title: "Autocorrect #{@offense.cop_name}",
            kind: Constant::CodeActionKind::QUICK_FIX,
            edit: Interface::WorkspaceEdit.new(
              document_changes: [
                Interface::TextDocumentEdit.new(
                  text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(
                    uri: @uri,
                    version: nil,
                  ),
                  edits: @offense.correctable? ? offense_replacements : [],
                ),
              ],
            ),
            is_preferred: true,
          )
        end

        sig { returns(Interface::Diagnostic) }
        def to_lsp_diagnostic
          if @offense.correctable?
            severity = RUBOCOP_TO_LSP_SEVERITY[@offense.severity.name]
            message = @offense.message
          else
            severity = Constant::DiagnosticSeverity::WARNING
            message = "#{@offense.message}\n\nThis offense is not auto-correctable.\n"
          end

          Interface::Diagnostic.new(
            message: message,
            source: "RuboCop",
            code: @offense.cop_name,
            severity: severity,
            range: Interface::Range.new(
              start: Interface::Position.new(
                line: @offense.line - 1,
                character: @offense.column,
              ),
              end: Interface::Position.new(
                line: @offense.last_line - 1,
                character: @offense.last_column,
              ),
            ),
            data: {
              correctable: @offense.correctable?,
              code_action: to_lsp_code_action,
            },
          )
        end

        private

        sig { returns(T::Array[Interface::TextEdit]) }
        def offense_replacements
          @offense.corrector.as_replacements.map do |range, replacement|
            Interface::TextEdit.new(
              range: Interface::Range.new(
                start: Interface::Position.new(line: range.line - 1, character: range.column),
                end: Interface::Position.new(line: range.last_line - 1, character: range.last_column),
              ),
              new_text: replacement,
            )
          end
        end
      end
    end
  end
end
