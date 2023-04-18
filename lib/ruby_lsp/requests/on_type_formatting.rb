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
        @line_end = T.let(scanner.find_char_position(position), Integer)
        line = T.must(@document.source[line_begin..@line_end])

        @indentation = T.let(find_indentation(line), Integer)
        @previous_line = T.let(line.strip.chomp, String)
        @position = position
        @edits = T.let([], T::Array[Interface::TextEdit])
        @trigger_character = trigger_character
      end

      sig { override.returns(T.all(T::Array[Interface::TextEdit], Object)) }
      def run
        case @trigger_character
        when "{"
          handle_curly_brace if @document.syntax_error?
        when "|"
          handle_pipe if @document.syntax_error?
        when "\n"
          if (comment_match = @previous_line.match(/^#(\s*)/))
            handle_comment_line(T.must(comment_match[1]))
          elsif @document.syntax_error?
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
        # If a keyword occurs in a line which appears be a comment or a string, we will not try to format it, since
        # it could be a coincidental match. This approach is not perfect, but it should cover most cases.
        return if @previous_line.start_with?(/["'#]/)

        return unless END_REGEXES.any? { |regex| regex.match?(@previous_line) }

        indents = " " * @indentation

        if @previous_line.include?("\n")
          # If the previous line has a line break, then it means there's content after the line break that triggered
          # this completion. For these cases, we want to add the `end` after the content and move the cursor back to the
          # keyword that triggered the completion

          line = @position[:line]

          # If there are enough lines in the document, we want to add the `end` token on the line below the extra
          # content. Otherwise, we want to insert and extra line break ourselves
          correction = if T.must(@document.source[@line_end..-1]).count("\n") >= 2
            line -= 1
            "#{indents}end"
          else
            "#{indents}\nend"
          end

          add_edit_with_text(correction, { line: @position[:line] + 1, character: @position[:character] })
          move_cursor_to(line, @indentation + 3)
        else
          # If there's nothing after the new line break that triggered the completion, then we want to add the `end` and
          # move the cursor to the body of the statement
          add_edit_with_text(" \n#{indents}end")
          move_cursor_to(@position[:line], @indentation + 2)
        end
      end

      sig { params(spaces: String).void }
      def handle_comment_line(spaces)
        add_edit_with_text("##{spaces}")
        move_cursor_to(@position[:line], @indentation + spaces.size + 1)
      end

      sig { params(text: String, position: Document::PositionShape).void }
      def add_edit_with_text(text, position = @position)
        pos = Interface::Position.new(
          line: position[:line],
          character: position[:character],
        )

        @edits << Interface::TextEdit.new(
          range: Interface::Range.new(start: pos, end: pos),
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
