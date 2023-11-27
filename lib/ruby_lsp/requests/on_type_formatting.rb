# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![On type formatting demo](../../on_type_formatting.gif)
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
          /\b(if|unless|for|while|class|module|until|def|case)\b.*/,
          /.*\s\bdo\b/,
        ],
        T::Array[Regexp],
      )

      sig { params(document: Document, position: Document::PositionShape, trigger_character: String).void }
      def initialize(document, position, trigger_character)
        super(document)

        @lines = T.let(@document.source.lines, T::Array[String])
        line = @lines[[position[:line] - 1, 0].max]

        @indentation = T.let(line ? find_indentation(line) : 0, Integer)
        @previous_line = T.let(line ? line.strip.chomp : "", String)
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
            match = /(?<=<<(-|~))(?<quote>['"`]?)(?<delimiter>\w+)\k<quote>/.match(@previous_line)
            heredoc_delimiter = match && match.named_captures["delimiter"]

            if heredoc_delimiter
              handle_heredoc_end(heredoc_delimiter)
            else
              handle_statement_end
            end
          end
        end

        @edits
      end

      private

      sig { void }
      def handle_pipe
        current_line = @lines[@position[:line]]
        return unless /((?<=do)|(?<={))\s+\|/.match?(current_line)

        line = T.must(current_line)

        # If the user inserts the closing pipe manually to the end of the block argument, we need to avoid adding
        # an additional one and remove the previous one.  This also helps to remove the user who accidentally
        # inserts another pipe after the autocompleted one.
        if line[..@position[:character]] =~ /(do|{)\s+\|[^|]*\|\|$/
          @edits << Interface::TextEdit.new(
            range: Interface::Range.new(
              start: Interface::Position.new(
                line: @position[:line],
                character: @position[:character],
              ),
              end: Interface::Position.new(
                line: @position[:line],
                character: @position[:character] + 1,
              ),
            ),
            new_text: "",
          )
        else
          add_edit_with_text("|")
        end

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
        current_line = @lines[@position[:line]]
        next_line = @lines[@position[:line] + 1]

        if current_line.nil? || current_line.strip.empty?
          add_edit_with_text("\n")
          add_edit_with_text("#{indents}end")
          move_cursor_to(@position[:line], @indentation + 2)
        elsif next_line.nil? || next_line.strip.empty?
          add_edit_with_text("#{indents}end\n", { line: @position[:line] + 1, character: @position[:character] })
          move_cursor_to(@position[:line] - 1, @indentation + @previous_line.size + 1)
        end
      end

      sig { params(delimiter: String).void }
      def handle_heredoc_end(delimiter)
        indents = " " * @indentation
        add_edit_with_text("\n")
        add_edit_with_text("#{indents}#{delimiter}")
        move_cursor_to(@position[:line], @indentation + 2)
      end

      sig { params(spaces: String).void }
      def handle_comment_line(spaces)
        add_edit_with_text("##{spaces}")
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
