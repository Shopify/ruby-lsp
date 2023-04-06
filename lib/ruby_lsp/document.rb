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

    sig { returns(Integer) }
    attr_reader :version

    sig { returns(String) }
    attr_reader :uri

    sig { params(source: String, version: Integer, uri: String, encoding: String).void }
    def initialize(source:, version:, uri:, encoding: Constant::PositionEncodingKind::UTF8)
      @cache = T.let({}, T::Hash[Symbol, T.untyped])
      @encoding = T.let(encoding, String)
      @source = T.let(source, String)
      @version = T.let(version, Integer)
      @uri = T.let(uri, String)
      @unparsed_edits = T.let([], T::Array[EditShape])
      @syntax_error = T.let(false, T::Boolean)
      @tree = T.let(SyntaxTree.parse(@source), T.nilable(SyntaxTree::Node))
    rescue SyntaxTree::Parser::ParseError
      @syntax_error = true
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

    sig { params(edits: T::Array[EditShape], version: Integer).void }
    def push_edits(edits, version:)
      edits.each do |edit|
        range = edit[:range]
        scanner = create_scanner

        start_position = scanner.find_char_position(range[:start])
        end_position = scanner.find_char_position(range[:end])

        @source[start_position...end_position] = edit[:text]
      end

      @version = version
      @unparsed_edits.concat(edits)
      @cache.clear
    end

    sig { void }
    def parse
      return if @unparsed_edits.empty?

      @unparsed_edits.clear
      @tree = SyntaxTree.parse(@source)
      @syntax_error = false
    rescue SyntaxTree::Parser::ParseError
      @syntax_error = true
    end

    sig { returns(T::Boolean) }
    def syntax_error?
      @syntax_error
    end

    sig { returns(T::Boolean) }
    def parsed?
      !@tree.nil?
    end

    sig { returns(Scanner) }
    def create_scanner
      Scanner.new(@source, @encoding)
    end

    sig do
      params(
        position: PositionShape,
        node_types: T::Array[T.class_of(SyntaxTree::Node)],
      ).returns([T.nilable(SyntaxTree::Node), T.nilable(SyntaxTree::Node)])
    end
    def locate_node(position, node_types: [])
      return [nil, nil] unless parsed?

      locate(T.must(@tree), create_scanner.find_char_position(position))
    end

    sig do
      params(
        node: SyntaxTree::Node,
        char_position: Integer,
        node_types: T::Array[T.class_of(SyntaxTree::Node)],
      ).returns([T.nilable(SyntaxTree::Node), T.nilable(SyntaxTree::Node)])
    end
    def locate(node, char_position, node_types: [])
      queue = T.let(node.child_nodes.compact, T::Array[T.nilable(SyntaxTree::Node)])
      closest = node
      parent = T.let(nil, T.nilable(SyntaxTree::Node))

      until queue.empty?
        candidate = queue.shift

        # Skip nil child nodes
        next if candidate.nil?

        # Add the next child_nodes to the queue to be processed
        queue.concat(candidate.child_nodes)

        # Skip if the current node doesn't cover the desired position
        loc = candidate.location
        next unless (loc.start_char...loc.end_char).cover?(char_position)

        # If the node's start character is already past the position, then we should've found the closest node
        # already
        break if char_position < loc.start_char

        # If there are node types to filter by, and the current node is not one of those types, then skip it
        next if node_types.any? && node_types.none? { |type| candidate.class == type }

        # If the current node is narrower than or equal to the previous closest node, then it is more precise
        closest_loc = closest.location
        if loc.end_char - loc.start_char <= closest_loc.end_char - closest_loc.start_char
          parent = closest
          closest = candidate
        end
      end

      [closest, parent]
    end

    class Scanner
      extend T::Sig

      LINE_BREAK = T.let(0x0A, Integer)
      # After character 0xFFFF, UTF-16 considers characters to have length 2 and we have to account for that
      SURROGATE_PAIR_START = T.let(0xFFFF, Integer)

      sig { params(source: String, encoding: String).void }
      def initialize(source, encoding)
        @current_line = T.let(0, Integer)
        @pos = T.let(0, Integer)
        @source = T.let(source.codepoints, T::Array[Integer])
        @encoding = encoding
      end

      # Finds the character index inside the source string for a given line and column
      sig { params(position: PositionShape).returns(Integer) }
      def find_char_position(position)
        # Find the character index for the beginning of the requested line
        until @current_line == position[:line]
          @pos += 1 until LINE_BREAK == @source[@pos]
          @pos += 1
          @current_line += 1
        end

        # The final position is the beginning of the line plus the requested column. If the encoding is UTF-16, we also
        # need to adjust for surrogate pairs
        requested_position = @pos + position[:character]

        if @encoding == Constant::PositionEncodingKind::UTF16
          requested_position -= utf_16_character_position_correction(@pos, requested_position)
        end

        requested_position
      end

      # Subtract 1 for each character after 0xFFFF in the current line from the column position, so that we hit the
      # right character in the UTF-8 representation
      sig { params(current_position: Integer, requested_position: Integer).returns(Integer) }
      def utf_16_character_position_correction(current_position, requested_position)
        utf16_unicode_correction = 0

        until current_position == requested_position
          codepoint = @source[current_position]
          utf16_unicode_correction += 1 if codepoint && codepoint > SURROGATE_PAIR_START

          current_position += 1
        end

        utf16_unicode_correction
      end
    end
  end
end
