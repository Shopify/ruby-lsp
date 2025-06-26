# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # The [on type formatting](https://microsoft.github.io/language-server-protocol/specification#textDocument_onTypeFormatting)
    # request formats code as the user is typing. For example, automatically adding `end` to class definitions.
    class OnTypeFormatting < Request
      class << self
        #: -> Interface::DocumentOnTypeFormattingRegistrationOptions
        def provider
          Interface::DocumentOnTypeFormattingRegistrationOptions.new(
            document_selector: nil,
            first_trigger_character: "{",
            more_trigger_character: ["\n", "|", "d"],
          )
        end
      end

      END_REGEXES = [
        /\b(if|unless|for|while|until)\b($|\s|\()/,
        /\b(class|module|def|case)\b($|\s)/,
        /.*\s\bdo\b($|\s)/,
      ] #: Array[Regexp]

      #: (RubyDocument document, Hash[Symbol, untyped] position, String trigger_character, String client_name) -> void
      def initialize(document, position, trigger_character, client_name)
        super()
        @document = document
        @lines = @document.source.lines #: Array[String]
        line = @lines[[position[:line] - 1, 0].max]

        @indentation = line ? find_indentation(line) : 0 #: Integer
        @previous_line = line ? line.strip.chomp : "" #: String
        @position = position
        @edits = [] #: Array[Interface::TextEdit]
        @trigger_character = trigger_character
        @client_name = client_name
      end

      # @override
      #: -> (Array[Interface::TextEdit] & Object)
      def perform
        case @trigger_character
        when "{"
          handle_curly_brace if @document.syntax_error?
        when "|"
          handle_pipe if @document.syntax_error?
        when "\n"
          # If the previous line is a simple comment, we'll add a comment continuation
          # But if it's a RBS signature starting with `#:`, we'll ignore it
          # so users can immediately continue typing the method definition
          if (comment_match = @previous_line.match(/^#(?!:)(\s*)/))
            handle_comment_line(
              comment_match[1], #: as !nil
            )
          elsif @document.syntax_error?
            match = /(<<((-|~)?))(?<quote>['"`]?)(?<delimiter>\w+)\k<quote>/.match(@previous_line)
            heredoc_delimiter = match && match.named_captures["delimiter"]

            if heredoc_delimiter
              handle_heredoc_end(heredoc_delimiter)
            else
              handle_statement_end
            end
          end
        when "d"
          auto_indent_after_end_keyword
        end

        @edits
      end

      private

      #: -> void
      def handle_pipe
        current_line = @lines[@position[:line]]
        return unless /((?<=do)|(?<={))\s+\|/.match?(current_line)

        line = current_line #: as !nil

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

      #: -> void
      def handle_curly_brace
        return unless /".*#\{/.match?(@previous_line)

        add_edit_with_text("}")
        move_cursor_to(@position[:line], @position[:character])
      end

      #: -> void
      def handle_statement_end
        # If a keyword occurs in a line which appears be a comment or a string, we will not try to format it, since
        # it could be a coincidental match. This approach is not perfect, but it should cover most cases.
        return if @previous_line.start_with?(/["'#]/)

        return unless END_REGEXES.any? { |regex| regex.match?(@previous_line) }

        indents = " " * @indentation
        current_line = @lines[@position[:line]]
        next_line = @lines[@position[:line] + 1]

        if current_line.nil? || current_line.strip.empty? || current_line.include?(")") || current_line.include?("]")
          add_edit_with_text("\n")
          add_edit_with_text("#{indents}end")
          move_cursor_to(@position[:line], @indentation + 2)
        elsif next_line.nil? || next_line.strip.empty?
          add_edit_with_text("#{indents}end\n", { line: @position[:line] + 1, character: @position[:character] })
          move_cursor_to(@position[:line] - 1, @indentation + @previous_line.size + 1)
        end
      end

      #: (String delimiter) -> void
      def handle_heredoc_end(delimiter)
        indents = " " * @indentation
        add_edit_with_text("\n")
        add_edit_with_text("#{indents}#{delimiter}")
        move_cursor_to(@position[:line], @indentation + 2)
      end

      #: (String spaces) -> void
      def handle_comment_line(spaces)
        add_edit_with_text("##{spaces}")
      end

      #: (String text, ?Hash[Symbol, untyped] position) -> void
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

      #: (Integer line, Integer character) -> void
      def move_cursor_to(line, character)
        return unless /Visual Studio Code|Cursor|VSCodium|Windsurf/.match?(@client_name)

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

      #: (String line) -> Integer
      def find_indentation(line)
        count = 0

        line.chars.each do |c|
          break unless c == " "

          count += 1
        end

        count
      end

      #: -> void
      def auto_indent_after_end_keyword
        current_line = @lines[@position[:line]]
        return unless current_line && current_line.strip == "end"

        node_context = @document.locate_node({
          line: @position[:line],
          character: @position[:character] - 1,
        })
        target = node_context.node

        statements = case target
        when Prism::IfNode, Prism::UnlessNode, Prism::ForNode, Prism::WhileNode, Prism::UntilNode
          target.statements
        end
        return unless statements

        current_indentation = find_indentation(current_line)
        statements.body.each do |node|
          loc = node.location
          next unless loc.start_column == current_indentation

          (loc.start_line..loc.end_line).each do |line|
            add_edit_with_text("  ", { line: line - 1, character: 0 })
          end
        end

        move_cursor_to(@position[:line], @position[:character])
      end
    end
  end
end
