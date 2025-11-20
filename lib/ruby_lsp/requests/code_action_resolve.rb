# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [code action resolve](https://microsoft.github.io/language-server-protocol/specification#codeAction_resolve)
    # request is used to to resolve the edit field for a given code action, if it is not already provided in the
    # textDocument/codeAction response. We can use it for scenarios that require more computation such as refactoring.
    class CodeActionResolve < Request
      include Support::Common

      NEW_VARIABLE_NAME = "new_variable"
      NEW_METHOD_NAME = "new_method"

      class CodeActionError < StandardError; end
      class EmptySelectionError < CodeActionError; end
      class InvalidTargetRangeError < CodeActionError; end
      class UnknownCodeActionError < CodeActionError; end

      #: (RubyDocument document, GlobalState global_state, Hash[Symbol, untyped] code_action) -> void
      def initialize(document, global_state, code_action)
        super()
        @document = document
        @global_state = global_state
        @code_action = code_action
      end

      # @override
      #: -> (Interface::CodeAction)
      def perform
        raise EmptySelectionError, "Invalid selection for refactor" if @document.source.empty?

        case @code_action[:title]
        when CodeActions::EXTRACT_TO_VARIABLE_TITLE
          refactor_variable
        when CodeActions::EXTRACT_TO_METHOD_TITLE
          refactor_method
        when CodeActions::TOGGLE_BLOCK_STYLE_TITLE
          switch_block_style
        when CodeActions::CREATE_ATTRIBUTE_READER,
             CodeActions::CREATE_ATTRIBUTE_WRITER,
             CodeActions::CREATE_ATTRIBUTE_ACCESSOR
          create_attribute_accessor
        else
          raise UnknownCodeActionError, "Unknown code action: #{@code_action[:title]}"
        end
      end

      private

      #: -> (Interface::CodeAction)
      def switch_block_style
        source_range = @code_action.dig(:data, :range)
        if source_range[:start] == source_range[:end]
          block_context = @document.locate_node(
            source_range[:start],
            node_types: [Prism::BlockNode],
          )
          node = block_context.node
          unless node.is_a?(Prism::BlockNode)
            raise InvalidTargetRangeError, "Cursor is not inside a block"
          end

          # Find the call node at the block node's start position.
          # This should be the call node whose block the cursor is inside of.
          call_context = RubyDocument.locate(
            @document.ast,
            node.location.cached_start_code_units_offset(@document.code_units_cache),
            node_types: [Prism::CallNode],
            code_units_cache: @document.code_units_cache,
          )
          target = call_context.node
          unless target.is_a?(Prism::CallNode) && target.block == node
            raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
          end
        else
          target = @document.locate_first_within_range(
            @code_action.dig(:data, :range),
            node_types: [Prism::CallNode],
          )

          unless target.is_a?(Prism::CallNode)
            raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
          end

          node = target.block
          unless node.is_a?(Prism::BlockNode)
            raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
          end
        end

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

      #: -> (Interface::CodeAction)
      def refactor_variable
        source_range = @code_action.dig(:data, :range)
        raise EmptySelectionError, "Invalid selection for refactor" if source_range[:start] == source_range[:end]

        start_index, end_index = @document.find_index_by_position(source_range[:start], source_range[:end])
        extracted_source = @document.source[start_index...end_index] #: as !nil

        # Find the closest statements node, so that we place the refactor in a valid position
        node_context = RubyDocument
          .locate(@document.ast,
            start_index,
            node_types: [
              Prism::StatementsNode,
              Prism::BlockNode,
            ],
            code_units_cache: @document.code_units_cache)

        closest_statements = node_context.node
        parent_statements = node_context.parent
        if closest_statements.nil? || closest_statements.child_nodes.compact.empty?
          raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
        end

        # Find the node with the end line closest to the requested position, so that we can place the refactor
        # immediately after that closest node
        closest_node = closest_statements.child_nodes.compact.min_by do |node|
          distance = source_range.dig(:start, :line) - (node.location.end_line - 1)
          distance <= 0 ? Float::INFINITY : distance
        end #: as !nil

        if closest_node.is_a?(Prism::MissingNode)
          raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
        end

        closest_node_loc = closest_node.location
        # If the parent expression is a single line block, then we have to extract it inside of the one-line block
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
          unless indentation_line
            raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
          end

          indentation = indentation_line[/\A */] #: as !nil
            .size

          target_range = {
            start: { line: target_line, character: indentation },
            end: { line: target_line, character: indentation },
          }

          line = lines[target_line]
          unless line
            raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
          end

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

      #: -> (Interface::CodeAction)
      def refactor_method
        source_range = @code_action.dig(:data, :range)
        raise EmptySelectionError, "Invalid selection for refactor" if source_range[:start] == source_range[:end]

        start_index, end_index = @document.find_index_by_position(source_range[:start], source_range[:end])
        extracted_source = @document.source[start_index...end_index] #: as !nil

        # Find the closest method declaration node, so that we place the refactor in a valid position
        node_context = RubyDocument.locate(
          @document.ast,
          start_index,
          node_types: [Prism::DefNode],
          code_units_cache: @document.code_units_cache,
        )
        closest_node = node_context.node
        unless closest_node
          raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
        end

        target_range = if closest_node.is_a?(Prism::DefNode)
          end_keyword_loc = closest_node.end_keyword_loc
          unless end_keyword_loc
            raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
          end

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

      #: (Hash[Symbol, untyped] range, String new_text) -> Interface::TextEdit
      def create_text_edit(range, new_text)
        Interface::TextEdit.new(
          range: Interface::Range.new(
            start: Interface::Position.new(line: range.dig(:start, :line), character: range.dig(:start, :character)),
            end: Interface::Position.new(line: range.dig(:end, :line), character: range.dig(:end, :character)),
          ),
          new_text: new_text,
        )
      end

      #: (Prism::BlockNode node, String? indentation) -> String
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

      #: (Prism::Node body, String? indentation) -> String
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

      #: -> (Interface::CodeAction)
      def create_attribute_accessor
        source_range = @code_action.dig(:data, :range)

        node = if source_range[:start] != source_range[:end]
          @document.locate_first_within_range(
            @code_action.dig(:data, :range),
            node_types: CodeActions::INSTANCE_VARIABLE_NODES,
          )
        end

        if node.nil?
          node_context = @document.locate_node(
            source_range[:start],
            node_types: CodeActions::INSTANCE_VARIABLE_NODES,
          )
          node = node_context.node

          unless CodeActions::INSTANCE_VARIABLE_NODES.include?(node.class)
            raise EmptySelectionError, "Invalid selection for refactor"
          end
        end

        node = node #: as Prism::InstanceVariableAndWriteNode | Prism::InstanceVariableOperatorWriteNode | Prism::InstanceVariableOrWriteNode | Prism::InstanceVariableReadNode | Prism::InstanceVariableTargetNode | Prism::InstanceVariableWriteNode

        node_context = @document.locate_node(
          {
            line: node.location.start_line,
            character: node.location.start_character_column,
          },
          node_types: [
            Prism::ClassNode,
            Prism::ModuleNode,
            Prism::SingletonClassNode,
          ],
        )
        closest_node = node_context.node
        if closest_node.nil?
          raise InvalidTargetRangeError, "Couldn't find an appropriate location to place extracted refactor"
        end

        attribute_name = node.name[1..]
        indentation = " " * (closest_node.location.start_column + 2)
        attribute_accessor_source = case @code_action[:title]
        when CodeActions::CREATE_ATTRIBUTE_READER
          "#{indentation}attr_reader :#{attribute_name}\n\n"
        when CodeActions::CREATE_ATTRIBUTE_WRITER
          "#{indentation}attr_writer :#{attribute_name}\n\n"
        when CodeActions::CREATE_ATTRIBUTE_ACCESSOR
          "#{indentation}attr_accessor :#{attribute_name}\n\n"
        end #: as !nil

        target_start_line = closest_node.location.start_line
        target_range = {
          start: { line: target_start_line, character: 0 },
          end: { line: target_start_line, character: 0 },
        }

        Interface::CodeAction.new(
          title: @code_action[:title],
          edit: Interface::WorkspaceEdit.new(
            document_changes: [
              Interface::TextDocumentEdit.new(
                text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(
                  uri: @code_action.dig(:data, :uri),
                  version: nil,
                ),
                edits: [
                  create_text_edit(target_range, attribute_accessor_source),
                ],
              ),
            ],
          ),
        )
      end
    end
  end
end
