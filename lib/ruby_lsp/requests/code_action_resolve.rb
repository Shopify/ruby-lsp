# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [code action resolve](https://microsoft.github.io/language-server-protocol/specification#codeAction_resolve)
    # request is used to to resolve the edit field for a given code action, if it is not already provided in the
    # textDocument/codeAction response. We can use it for scenarios that require more computation such as refactoring.
    class CodeActionResolve < Request
      extend T::Sig
      include Support::Common

      NEW_VARIABLE_NAME = "new_variable"
      NEW_METHOD_NAME = "new_method"

      class CodeActionError < StandardError; end

      class Error < ::T::Enum
        enums do
          EmptySelection = new
          InvalidTargetRange = new
          UnknownCodeAction = new
        end
      end

      sig { params(document: RubyDocument, global_state: GlobalState, code_action: T::Hash[Symbol, T.untyped]).void }
      def initialize(document, global_state, code_action)
        super()
        @document = document
        @global_state = global_state
        @code_action = code_action
      end

      sig { override.returns(T.any(Interface::CodeAction, Error)) }
      def perform
        return Error::EmptySelection if @document.source.empty?

        case @code_action[:title]
        when CodeActions::EXTRACT_TO_VARIABLE_TITLE
          refactor_variable
        when CodeActions::EXTRACT_TO_METHOD_TITLE
          refactor_method
        when CodeActions::TOGGLE_BLOCK_STYLE_TITLE
          switch_block_style
        else
          Error::UnknownCodeAction
        end
      end

      private

      sig { returns(T.any(Interface::CodeAction, Error)) }
      def switch_block_style
        source_range = @code_action.dig(:data, :range)
        return Error::EmptySelection if source_range[:start] == source_range[:end]

        target = @document.locate_first_within_range(
          @code_action.dig(:data, :range),
          node_types: [Prism::CallNode],
        )

        return Error::InvalidTargetRange unless target.is_a?(Prism::CallNode)

        node = target.block
        return Error::InvalidTargetRange unless node.is_a?(Prism::BlockNode)

        indentation = " " * target.location.start_column unless node.opening_loc.slice == "do"

        Interface::CodeAction.new(
          title: CodeActions::TOGGLE_BLOCK_STYLE_TITLE,
          edit: Interface::WorkspaceEdit.new(
            document_changes: [
              Interface::TextDocumentEdit.new(
                text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(
                  uri: @code_action.dig(:data, :uri),
                  version: nil,
                ),
                edits: [
                  Interface::TextEdit.new(
                    range: range_from_location(node.location),
                    new_text: recursively_switch_nested_block_styles(node, indentation),
                  ),
                ],
              ),
            ],
          ),
        )
      end

      sig { returns(T.any(Interface::CodeAction, Error)) }
      def refactor_variable
        source_range = @code_action.dig(:data, :range)
        return Error::EmptySelection if source_range[:start] == source_range[:end]

        scanner = @document.create_scanner
        start_index = scanner.find_char_position(source_range[:start])
        end_index = scanner.find_char_position(source_range[:end])
        extracted_source = T.must(@document.source[start_index...end_index])

        # Find the closest statements node, so that we place the refactor in a valid position
        node_context = RubyDocument
          .locate(@document.parse_result.value, start_index, node_types: [Prism::StatementsNode, Prism::BlockNode])

        closest_statements = node_context.node
        parent_statements = node_context.parent
        return Error::InvalidTargetRange if closest_statements.nil? || closest_statements.child_nodes.compact.empty?

        # Find the node with the end line closest to the requested position, so that we can place the refactor
        # immediately after that closest node
        closest_node = T.must(closest_statements.child_nodes.compact.min_by do |node|
          distance = source_range.dig(:start, :line) - (node.location.end_line - 1)
          distance <= 0 ? Float::INFINITY : distance
        end)

        return Error::InvalidTargetRange if closest_node.is_a?(Prism::MissingNode)

        closest_node_loc = closest_node.location
        # If the parent expression is a single line block, then we have to extract it inside of the oneline block
        if parent_statements.is_a?(Prism::BlockNode) &&
            parent_statements.location.start_line == parent_statements.location.end_line

          variable_source = " #{NEW_VARIABLE_NAME} = #{extracted_source};"
          character = source_range.dig(:start, :character) - 1
          target_range = {
            start: { line: closest_node_loc.end_line - 1, character: character },
            end: { line: closest_node_loc.end_line - 1, character: character },
          }
        else
          # If the closest node covers the requested location, then we're extracting a statement nested inside of it. In
          # that case, we want to place the extraction at the start of the closest node (one line above). Otherwise, we
          # want to place the extract right below the closest node
          if closest_node_loc.start_line - 1 <= source_range.dig(
            :start,
            :line,
          ) && closest_node_loc.end_line - 1 >= source_range.dig(:end, :line)
            indentation_line_number = closest_node_loc.start_line - 1
            target_line = indentation_line_number
          else
            target_line = closest_node_loc.end_line
            indentation_line_number = closest_node_loc.end_line - 1
          end

          lines = @document.source.lines

          indentation_line = lines[indentation_line_number]
          return Error::InvalidTargetRange unless indentation_line

          indentation = T.must(indentation_line[/\A */]).size

          target_range = {
            start: { line: target_line, character: indentation },
            end: { line: target_line, character: indentation },
          }

          line = lines[target_line]
          return Error::InvalidTargetRange unless line

          variable_source = if line.strip.empty?
            "\n#{" " * indentation}#{NEW_VARIABLE_NAME} = #{extracted_source}"
          else
            "#{NEW_VARIABLE_NAME} = #{extracted_source}\n#{" " * indentation}"
          end
        end

        Interface::CodeAction.new(
          title: CodeActions::EXTRACT_TO_VARIABLE_TITLE,
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

      sig { returns(T.any(Interface::CodeAction, Error)) }
      def refactor_method
        source_range = @code_action.dig(:data, :range)
        return Error::EmptySelection if source_range[:start] == source_range[:end]

        scanner = @document.create_scanner
        start_index = scanner.find_char_position(source_range[:start])
        end_index = scanner.find_char_position(source_range[:end])
        extracted_source = T.must(@document.source[start_index...end_index])

        # Find the closest method declaration node, so that we place the refactor in a valid position
        node_context = RubyDocument.locate(
          @document.parse_result.value,
          start_index,
          node_types: [Prism::DefNode],
          encoding: @global_state.encoding,
        )
        closest_node = node_context.node
        return Error::InvalidTargetRange unless closest_node

        target_range = if closest_node.is_a?(Prism::DefNode)
          end_keyword_loc = closest_node.end_keyword_loc
          return Error::InvalidTargetRange unless end_keyword_loc

          end_line = end_keyword_loc.end_line - 1
          character = end_keyword_loc.end_column
          indentation = " " * end_keyword_loc.start_column

          new_method_source = <<~RUBY.chomp


            #{indentation}def #{NEW_METHOD_NAME}
            #{indentation}  #{extracted_source}
            #{indentation}end
          RUBY

          {
            start: { line: end_line, character: character },
            end: { line: end_line, character: character },
          }
        else
          new_method_source = <<~RUBY
            #{indentation}def #{NEW_METHOD_NAME}
            #{indentation}  #{extracted_source.gsub("\n", "\n  ")}
            #{indentation}end

          RUBY

          line = [0, source_range.dig(:start, :line) - 1].max
          {
            start: { line: line, character: source_range.dig(:start, :character) },
            end: { line: line, character: source_range.dig(:start, :character) },
          }
        end

        Interface::CodeAction.new(
          title: CodeActions::EXTRACT_TO_METHOD_TITLE,
          edit: Interface::WorkspaceEdit.new(
            document_changes: [
              Interface::TextDocumentEdit.new(
                text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(
                  uri: @code_action.dig(:data, :uri),
                  version: nil,
                ),
                edits: [
                  create_text_edit(target_range, new_method_source),
                  create_text_edit(source_range, NEW_METHOD_NAME),
                ],
              ),
            ],
          ),
        )
      end

      sig { params(range: T::Hash[Symbol, T.untyped], new_text: String).returns(Interface::TextEdit) }
      def create_text_edit(range, new_text)
        Interface::TextEdit.new(
          range: Interface::Range.new(
            start: Interface::Position.new(line: range.dig(:start, :line), character: range.dig(:start, :character)),
            end: Interface::Position.new(line: range.dig(:end, :line), character: range.dig(:end, :character)),
          ),
          new_text: new_text,
        )
      end

      sig { params(node: Prism::BlockNode, indentation: T.nilable(String)).returns(String) }
      def recursively_switch_nested_block_styles(node, indentation)
        parameters = node.parameters
        body = node.body

        # We use the indentation to differentiate between do...end and brace style blocks because only the do...end
        # style requires the indentation to build the edit.
        #
        # If the block is using `do...end` style, we change it to a single line brace block. Newlines are turned into
        # semi colons, so that the result is valid Ruby code and still a one liner. If the block is using brace style,
        # we do the opposite and turn it into a `do...end` block, making all semi colons into newlines.
        source = +""

        if indentation
          source << "do"
          source << " #{parameters.slice}" if parameters
          source << "\n#{indentation}  "
          source << switch_block_body(body, indentation) if body
          source << "\n#{indentation}end"
        else
          source << "{ "
          source << "#{parameters.slice} " if parameters
          source << switch_block_body(body, nil) if body
          source << "}"
        end

        source
      end

      sig { params(body: Prism::Node, indentation: T.nilable(String)).returns(String) }
      def switch_block_body(body, indentation)
        # Check if there are any nested blocks inside of the current block
        body_loc = body.location
        nested_block = @document.locate_first_within_range(
          {
            start: { line: body_loc.start_line - 1, character: body_loc.start_column },
            end: { line: body_loc.end_line - 1, character: body_loc.end_column },
          },
          node_types: [Prism::BlockNode],
        )

        body_content = body.slice.dup

        # If there are nested blocks, then we change their style too and we have to mutate the string using the
        # relative position in respect to the beginning of the body
        if nested_block.is_a?(Prism::BlockNode)
          location = nested_block.location
          correction_start = location.start_offset - body_loc.start_offset
          correction_end = location.end_offset - body_loc.start_offset
          next_indentation = indentation ? "#{indentation}  " : nil

          body_content[correction_start...correction_end] =
            recursively_switch_nested_block_styles(nested_block, next_indentation)
        end

        indentation ? body_content.gsub(";", "\n") : "#{body_content.gsub("\n", ";")} "
      end
    end
  end
end
