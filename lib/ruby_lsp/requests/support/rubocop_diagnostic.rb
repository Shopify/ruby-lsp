# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class RuboCopDiagnostic
        extend T::Sig

        RUBOCOP_TO_LSP_SEVERITY = T.let(
          {
            info: Constant::DiagnosticSeverity::HINT,
            refactor: Constant::DiagnosticSeverity::INFORMATION,
            convention: Constant::DiagnosticSeverity::INFORMATION,
            warning: Constant::DiagnosticSeverity::WARNING,
            error: Constant::DiagnosticSeverity::ERROR,
            fatal: Constant::DiagnosticSeverity::ERROR,
          }.freeze,
          T::Hash[Symbol, Integer],
        )

        sig { params(offense: RuboCop::Cop::Offense, uri: URI::Generic).void }
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
                    uri: @uri.to_s,
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
          Interface::Diagnostic.new(
            message: message,
            source: "RuboCop",
            code: @offense.cop_name,
            code_description: code_description,
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

        sig { returns(String) }
        def message
          message  = @offense.message
          message += "\n\nThis offense is not auto-correctable.\n" unless @offense.correctable?
          message
        end

        sig { returns(T.nilable(Integer)) }
        def severity
          RUBOCOP_TO_LSP_SEVERITY[@offense.severity.name]
        end

        sig { returns(T.nilable(Interface::CodeDescription)) }
        def code_description
          doc_url = RuboCopRunner.find_cop_by_name(@offense.cop_name)&.documentation_url
          Interface::CodeDescription.new(href: doc_url) if doc_url
        end

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
