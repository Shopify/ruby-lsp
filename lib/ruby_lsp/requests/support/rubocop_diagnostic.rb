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

        # TODO: avoid passing document once we have alternative ways to get at
        # encoding and file source
        sig { params(document: Document, offense: RuboCop::Cop::Offense, uri: URI::Generic).void }
        def initialize(document, offense, uri)
          @document = document
          @offense = offense
          @uri = uri
        end

        sig { returns(T::Array[Interface::CodeAction]) }
        def to_lsp_code_actions
          code_actions = []

          code_actions << autocorrect_action if @offense.correctable?
          code_actions << disable_line_action

          code_actions
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
              code_actions: to_lsp_code_actions,
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

        sig { returns(Interface::CodeAction) }
        def autocorrect_action
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

        sig { returns(Interface::CodeAction) }
        def disable_line_action
          Interface::CodeAction.new(
            title: "Disable #{@offense.cop_name} for this line",
            kind: Constant::CodeActionKind::QUICK_FIX,
            edit: Interface::WorkspaceEdit.new(
              document_changes: [
                Interface::TextDocumentEdit.new(
                  text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(
                    uri: @uri.to_s,
                    version: nil,
                  ),
                  edits: line_disable_comment,
                ),
              ],
            ),
          )
        end

        sig { returns(T::Array[Interface::TextEdit]) }
        def line_disable_comment
          new_text = if @offense.source_line.include?(" # rubocop:disable ")
            ",#{@offense.cop_name}"
          else
            " # rubocop:disable #{@offense.cop_name}"
          end

          eol = Interface::Position.new(
            line: @offense.line - 1,
            character: length_of_line(@offense.source_line),
          )

          # TODO: fails for multiline strings - may be preferable to use block
          # comments to disable some offenses
          inline_comment = Interface::TextEdit.new(
            range: Interface::Range.new(start: eol, end: eol),
            new_text: new_text,
          )

          [inline_comment]
        end

        sig { params(line: String).returns(Integer) }
        def length_of_line(line)
          if @document.encoding == Constant::PositionEncodingKind::UTF16
            line_length = 0
            line.codepoints.each do |codepoint|
              line_length += 1
              if codepoint > RubyLsp::Document::Scanner::SURROGATE_PAIR_START
                line_length += 1
              end
            end
            line_length
          else
            line.length
          end
        end
      end
    end
  end
end
