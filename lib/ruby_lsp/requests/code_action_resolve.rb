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
    # 1 + 1 # Select the text and use Refactor: Extract Variable
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
          InvalidTargetRange = new
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

        return Error::InvalidTargetRange if @document.syntax_error?

        scanner = @document.create_scanner
        start_index = scanner.find_char_position(source_range[:start])
        end_index = scanner.find_char_position(source_range[:end])
        extracted_source = T.must(@document.source[start_index...end_index])

        # Find the closest statements node, so that we place the refactor in a valid position
        closest_statements = @document
          .locate(T.must(@document.tree), start_index, node_types: [SyntaxTree::Statements])
          .first
        return Error::InvalidTargetRange if closest_statements.nil?

        # Find the node with the end line closest to the requested position, so that we can place the refactor
        # immediately after that closest node
        closest_node = closest_statements.child_nodes.compact.min_by do |node|
          distance = source_range.dig(:start, :line) - (node.location.end_line - 1)
          distance <= 0 ? Float::INFINITY : distance
        end

        # When trying to extract the first node inside of a statements block, then we can just select one line above it
        target_line = if closest_node == closest_statements.child_nodes.first
          closest_node.location.start_line - 1
        else
          closest_node.location.end_line
        end

        lines = @document.source.lines
        indentation = T.must(T.must(lines[target_line - 1])[/\A */]).size

        target_range = {
          start: { line: target_line, character: indentation },
          end: { line: target_line, character: indentation },
        }

        variable_source = if T.must(lines[target_line]).strip.empty?
          "\n#{" " * indentation}#{NEW_VARIABLE_NAME} = #{extracted_source}"
        else
          "#{NEW_VARIABLE_NAME} = #{extracted_source}\n#{" " * indentation}"
        end

        Interface::CodeAction.new(
          title: "Refactor: Extract Variable",
          edit: Interface::WorkspaceEdit.new(
            document_changes: [
              Interface::TextDocumentEdit.new(
                text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(
                  uri: @code_action.dig(:data, :uri),
                  version: nil,
                ),
                edits: [
                  create_text_edit(source_range, NEW_VARIABLE_NAME),
                  create_text_edit(target_range, variable_source),
                ],
              ),
            ],
          ),
        )
      end

      private

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
