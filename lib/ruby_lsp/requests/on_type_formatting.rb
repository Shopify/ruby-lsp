# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![On type formatting demo](../../misc/on_type_formatting.gif)
    #
    # The [on type formatting](https://microsoft.github.io/language-server-protocol/specification#textDocument_onTypeFormatting)
    # request formats code as the user is typing. For example, automatically adding `end` to class definitions.
    #
    # # Example
    #
    # ```ruby
    # class Foo # <-- upon adding a line break, on type formatting is triggered
    #   # <-- cursor ends up here
    # end # <-- end is automatically added
    # ```
    class OnTypeFormatting < BaseRequest
      extend T::Sig

      END_REGEXES = T.let(
        [
          /(if|unless|for|while|class|module|until|def|case).*/,
          /.*\sdo/,
        ],
        T::Array[Regexp],
      )

      sig { params(document: Document, position: Document::PositionShape, trigger_character: String).void }
      def initialize(document, position, trigger_character)
        super(document)

        scanner = document.create_scanner
        line_begin = position[:line] == 0 ? 0 : scanner.find_char_position({ line: position[:line] - 1, character: 0 })
        line_end = scanner.find_char_position(position)
        line = T.must(@document.source[line_begin..line_end])

        @indentation = T.let(find_indentation(line), Integer)
        @previous_line = T.let(line.strip.chomp, String)
        @position = position
        @edits = T.let([], T::Array[Interface::TextEdit])
        @trigger_character = trigger_character
      end

      sig { override.returns(T.nilable(T.all(T::Array[Interface::TextEdit], Object))) }
      def run
        case @trigger_character
        when "{"
          handle_curly_brace if @document.syntax_errors?
        when "|"
          handle_pipe if @document.syntax_errors?
        when "\n"
          if (comment_match = @previous_line.match(/^#(\s*)/))
            handle_comment_line(T.must(comment_match[1]))
          elsif @document.syntax_errors?
            handle_statement_end
          end
        end

        @edits
      end

      private

      sig { void }
      def handle_pipe
        return unless /((?<=do)|(?<={))\s+\|/.match?(@previous_line)

        add_edit_with_text("|")
        move_cursor_to(@position[:line], @position[:character])
      end

      sig { void }
      def handle_curly_brace
        return unless /".*#\{/.match?(@previous_line)

        add_edit_with_text("}")
        move_cursor_to(@position[:line], @position[:character])
      end

      sig { void }
      def handle_statement_end
        return unless END_REGEXES.any? { |regex| regex.match?(@previous_line) }

        indents = " " * @indentation

        add_edit_with_text(" \n#{indents}end")
        move_cursor_to(@position[:line], @indentation + 2)
      end

      sig { params(spaces: String).void }
      def handle_comment_line(spaces)
        add_edit_with_text("##{spaces}")
        move_cursor_to(@position[:line], @indentation + spaces.size + 1)
      end

      sig { params(text: String).void }
      def add_edit_with_text(text)
        position = Interface::Position.new(
          line: @position[:line],
          character: @position[:character],
        )

        @edits << Interface::TextEdit.new(
          range: Interface::Range.new(
            start: position,
            end: position,
          ),
          new_text: text,
        )
      end

      sig { params(line: Integer, character: Integer).void }
      def move_cursor_to(line, character)
        position = Interface::Position.new(
          line: line,
          character: character,
        )

        # The $0 is a special snippet anchor that moves the cursor to that given position. See the snippets
        # documentation for more information:
        # https://code.visualstudio.com/docs/editor/userdefinedsnippets#_create-your-own-snippets
        @edits << Interface::TextEdit.new(
          range: Interface::Range.new(
            start: position,
            end: position,
          ),
          new_text: "$0",
        )
      end

      sig { params(line: String).returns(Integer) }
      def find_indentation(line)
        count = 0

        line.chars.each do |c|
          break unless c == " "

          count += 1
        end

        count
      end
    end
  end
end
