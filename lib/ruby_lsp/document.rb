# frozen_string_literal: true

require "strscan"

module RubyLsp
  class Document
    attr_reader :tree, :source

    def initialize(source)
      @tree = SyntaxTree.parse(source)
      @cache = {}
      @source = source
      @parsable_source = source.dup
    end

    def ==(other)
      @source == other.source
    end

    def reset(source)
      @tree = SyntaxTree.parse(source)
      @source = source
      @parsable_source = source.dup
      @cache.clear
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

      @tree = SyntaxTree.parse(@source)
      @cache.clear
      @parsable_source = @source.dup
    rescue SyntaxTree::Parser::ParseError
      # If the new edits caused a syntax error, make all edits blank spaces and line breaks to adjust the line and
      # column numbers. This is attempt to make the document parsable while partial edits are being applied
      edits.each do |edit|
        next if edit[:text].empty? # skip deletions, since they may have caused the syntax error

        apply_edit(@parsable_source, edit[:range], edit[:text].gsub(/[^\r\n]/, " "))
      end

      @tree = SyntaxTree.parse(@parsable_source)
    rescue SyntaxTree::Parser::ParseError
      # If we can't parse the source even after emptying the edits, then just fallback to the previous source
    end

    private

    def apply_edit(source, range, text)
      scanner = Scanner.new(source)
      start_position = scanner.find_position(range[:start])
      end_position = scanner.find_position(range[:end])

      source[start_position...end_position] = text
    end

    class Scanner
      def initialize(source)
        @source = source
        @scanner = StringScanner.new(source)
        @current_line = 0
      end

      def find_position(position)
        # Move the string scanner counting line breaks until we reach the right line
        until @current_line == position[:line]
          @scanner.scan_until(/\R/)
          @current_line += 1
        end

        @scanner.pos + position[:character]
      end
    end
  end
end
