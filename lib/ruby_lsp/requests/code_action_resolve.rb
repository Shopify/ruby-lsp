# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Code action resolve demo](../../misc/code_action_resolve.gif)
    #
    # The [code action resolve](https://microsoft.github.io/language-server-protocol/specification#codeAction_resolve)
    # request is used to to resolve the edit field for a given code action, if it is not already provided in the
    # textDocument/codeAction response. We can use it for scenarios that require more computation such as refactoring.
    #
    # # Example: Extract to variable
    #
    # ```ruby
    # # Before:
    # 1 + 1 # Select the text and use Refactor: Extract variable
    #
    # # After:
    # new_variable = 1 + 1
    # new_variable
    #
    # ```
    #
    class CodeActionResolve < BaseRequest
      extend T::Sig
      NEW_VARIABLE_NAME = "new_variable"

      class CodeActionError < StandardError; end

      class Error < ::T::Enum
        enums do
          EmptySelection = new
        end
      end

      sig { params(document: Document, code_action: T::Hash[Symbol, T.untyped]).void }
      def initialize(document, code_action)
        super(document)

        @code_action = code_action
      end

      sig { override.returns(T.any(Interface::CodeAction, Error)) }
      def run
        source_range = @code_action.dig(:data, :range)
        return Error::EmptySelection if source_range[:start] == source_range[:end]

        scanner = @document.create_scanner
        start_index = scanner.find_char_position(source_range[:start])
        end_index = scanner.find_char_position(source_range[:end])
        extraction_source = T.must(@document.source[start_index...end_index])
        source_line_indentation = T.must(T.must(@document.source.lines[source_range.dig(:start, :line)])[/\A */]).size

        Interface::CodeAction.new(
          title: "Refactor: Extract variable",
          edit: Interface::WorkspaceEdit.new(
            document_changes: [
              Interface::TextDocumentEdit.new(
                text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(
                  uri: @code_action.dig(:data, :uri),
                  version: nil,
                ),
                edits: edits_to_extract_variable(source_range, extraction_source, source_line_indentation),
              ),
            ],
          ),
        )
      end

      private

      sig do
        params(range: Document::RangeShape, source: String, indentation: Integer)
          .returns(T::Array[Interface::TextEdit])
      end
      def edits_to_extract_variable(range, source, indentation)
        target_range = {
          start: { line: range.dig(:start, :line), character: indentation },
          end: { line: range.dig(:start, :line), character: indentation },
        }

        [
          create_text_edit(range, NEW_VARIABLE_NAME),
          create_text_edit(target_range, "#{NEW_VARIABLE_NAME} = #{source}\n#{" " * indentation}"),
        ]
      end

      sig { params(range: Document::RangeShape, new_text: String).returns(Interface::TextEdit) }
      def create_text_edit(range, new_text)
        Interface::TextEdit.new(
          range: Interface::Range.new(
            start: Interface::Position.new(line: range.dig(:start, :line), character: range.dig(:start, :character)),
            end: Interface::Position.new(line: range.dig(:end, :line), character: range.dig(:end, :character)),
          ),
          new_text: new_text,
        )
      end
    end
  end
end
