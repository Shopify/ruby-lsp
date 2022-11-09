# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Document
    extend T::Sig

    PositionShape = T.type_alias { { line: Integer, character: Integer } }
    RangeShape = T.type_alias { { start: PositionShape, end: PositionShape } }
    EditShape = T.type_alias { { range: RangeShape, text: String } }

    sig { returns(T.nilable(SyntaxTree::Node)) }
    attr_reader :tree

    sig { returns(String) }
    attr_reader :source

    sig { returns(T::Array[EditShape]) }
    attr_reader :syntax_error_edits

    sig { params(source: String).void }
    def initialize(source)
      @cache = T.let({}, T::Hash[Symbol, T.untyped])
      @syntax_error_edits = T.let([], T::Array[EditShape])
      @source = T.let(source, String)
      @parsable_source = T.let(source.dup, String)
      @unparsed_edits = T.let([], T::Array[EditShape])
      @tree = T.let(SyntaxTree.parse(@source), T.nilable(SyntaxTree::Node))
    rescue SyntaxTree::Parser::ParseError
      # Do not raise if we failed to parse
    end

    sig { params(other: Document).returns(T::Boolean) }
    def ==(other)
      @source == other.source
    end

    sig do
      type_parameters(:T)
        .params(
          request_name: Symbol,
          block: T.proc.params(document: Document).returns(T.type_parameter(:T)),
        ).returns(T.type_parameter(:T))
    end
    def cache_fetch(request_name, &block)
      cached = @cache[request_name]
      return cached if cached

      result = block.call(self)
      @cache[request_name] = result
      result
    end

    sig { params(edits: T::Array[EditShape]).void }
    def push_edits(edits)
      # Apply the edits on the real source
      edits.each { |edit| apply_edit(@source, edit[:range], edit[:text]) }

      @unparsed_edits.concat(edits)
      @cache.clear
    end

    sig { void }
    def parse
      return if @unparsed_edits.empty?

      @tree = SyntaxTree.parse(@source)
      @syntax_error_edits.clear
      @unparsed_edits.clear
      @parsable_source = @source.dup
    rescue SyntaxTree::Parser::ParseError
      @syntax_error_edits = @unparsed_edits
      update_parsable_source(@unparsed_edits)
    end

    sig { returns(T::Boolean) }
    def syntax_errors?
      @syntax_error_edits.any?
    end

    sig { returns(T::Boolean) }
    def parsed?
      !@tree.nil?
    end

    private

    sig { params(edits: T::Array[EditShape]).void }
    def update_parsable_source(edits)
      # If the new edits caused a syntax error, make all edits blank spaces and line breaks to adjust the line and
      # column numbers. This is attempt to make the document parsable while partial edits are being applied
      edits.each do |edit|
        next if edit[:text].empty? # skip deletions, since they may have caused the syntax error

        apply_edit(@parsable_source, edit[:range], edit[:text].gsub(/[^\r\n]/, " "))
      end

      @tree = SyntaxTree.parse(@parsable_source)
    rescue StandardError
      # Trying to maintain a parsable source when there are syntax errors is a best effort. If we fail to apply edits or
      # parse, just ignore it
    end

    sig { params(source: String, range: RangeShape, text: String).void }
    def apply_edit(source, range, text)
      scanner = Scanner.new(source)
      start_position = scanner.find_position(range[:start])
      end_position = scanner.find_position(range[:end])

      source[start_position...end_position] = text
    end

    class Scanner
      extend T::Sig

      sig { params(source: String).void }
      def initialize(source)
        @current_line = T.let(0, Integer)
        @pos = T.let(0, Integer)
        @source = source
      end

      sig { params(position: PositionShape).returns(Integer) }
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
