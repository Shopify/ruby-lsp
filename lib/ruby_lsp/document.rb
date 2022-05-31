# typed: false
# frozen_string_literal: true

module RubyLsp
  class Document
    attr_reader :tree, :source, :syntax_error_edits

    def initialize(source)
      @tree = SyntaxTree.parse(source)
      @cache = {}
      @syntax_error_edits = []
      @source = source
      @parsable_source = source.dup
    end

    def ==(other)
      @source == other.source
    end

    def cache_fetch(request_name)
      cached = @cache[request_name]
      return cached if cached

      result = yield(self)
      @cache[request_name] = result
      result
    end

    def push_edits(edits)
      # Apply the edits on the real source
      edits.each { |edit| apply_edit(@source, edit[:range], edit[:text]) }

      @cache.clear
      @tree = SyntaxTree.parse(@source)
      @syntax_error_edits.clear
      @parsable_source = @source.dup
      nil
    rescue SyntaxTree::Parser::ParseError
      update_parsable_source(edits)
    end

    def syntax_errors?
      @syntax_error_edits.any?
    end

    private

    def update_parsable_source(edits)
      # If the new edits caused a syntax error, make all edits blank spaces and line breaks to adjust the line and
      # column numbers. This is attempt to make the document parsable while partial edits are being applied
      edits.each do |edit|
        @syntax_error_edits << edit
        next if edit[:text].empty? # skip deletions, since they may have caused the syntax error

        apply_edit(@parsable_source, edit[:range], edit[:text].gsub(/[^\r\n]/, " "))
      end

      @tree = SyntaxTree.parse(@parsable_source)
    rescue SyntaxTree::Parser::ParseError
      # If we can't parse the source even after emptying the edits, then just fallback to the previous source
    end

    def apply_edit(source, range, text)
      scanner = Scanner.new(source)
      start_position = scanner.find_position(range[:start])
      end_position = scanner.find_position(range[:end])

      source[start_position...end_position] = text
    end

    class Scanner
      def initialize(source)
        @current_line = 0
        @pos = 0
        @source = source
      end

      def find_position(position)
        until @current_line == position[:line]
          @pos += 1 until /\R/.match?(@source[@pos])
          @pos += 1
          @current_line += 1
        end

        @pos + position[:character]
      end
    end
  end
end
