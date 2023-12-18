# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Document
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { returns(Prism::ParseResult) }
    attr_reader :parse_result

    sig { returns(String) }
    attr_reader :source

    sig { returns(Integer) }
    attr_reader :version

    sig { returns(URI::Generic) }
    attr_reader :uri

    sig { returns(String) }
    attr_reader :encoding

    sig { params(source: String, version: Integer, uri: URI::Generic, encoding: String).void }
    def initialize(source:, version:, uri:, encoding: Constant::PositionEncodingKind::UTF8)
      @cache = T.let({}, T::Hash[String, T.untyped])
      @encoding = T.let(encoding, String)
      @source = T.let(source, String)
      @version = T.let(version, Integer)
      @uri = T.let(uri, URI::Generic)
      @needs_parsing = T.let(true, T::Boolean)
      @parse_result = T.let(parse, Prism::ParseResult)
    end

    sig { returns(Prism::ProgramNode) }
    def tree
      @parse_result.value
    end

    sig { returns(T::Array[Prism::Comment]) }
    def comments
      @parse_result.comments
    end

    sig { params(other: Document).returns(T::Boolean) }
    def ==(other)
      @source == other.source
    end

    # TODO: remove this method once all nonpositional requests have been migrated to the listener pattern
    sig do
      type_parameters(:T)
        .params(
          request_name: String,
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

    sig { type_parameters(:T).params(request_name: String, value: T.type_parameter(:T)).returns(T.type_parameter(:T)) }
    def cache_set(request_name, value)
      @cache[request_name] = value
    end

    sig { params(request_name: String).returns(T.untyped) }
    def cache_get(request_name)
      @cache[request_name]
    end

    sig { params(edits: T::Array[T::Hash[Symbol, T.untyped]], version: Integer).void }
    def push_edits(edits, version:)
      edits.each do |edit|
        range = edit[:range]
        scanner = create_scanner

        start_position = scanner.find_char_position(range[:start])
        end_position = scanner.find_char_position(range[:end])

        @source[start_position...end_position] = edit[:text]
      end

      @version = version
      @needs_parsing = true
      @cache.clear
    end

    sig { abstract.returns(Prism::ParseResult) }
    def parse; end

    sig { returns(T::Boolean) }
    def syntax_error?
      @parse_result.failure?
    end

    sig { returns(Scanner) }
    def create_scanner
      Scanner.new(@source, @encoding)
    end

    sig do
      params(
        position: T::Hash[Symbol, T.untyped],
        node_types: T::Array[T.class_of(Prism::Node)],
      ).returns([T.nilable(Prism::Node), T.nilable(Prism::Node), T::Array[String]])
    end
    def locate_node(position, node_types: [])
      locate(@parse_result.value, create_scanner.find_char_position(position), node_types: node_types)
    end

    sig do
      params(
        node: Prism::Node,
        char_position: Integer,
        node_types: T::Array[T.class_of(Prism::Node)],
      ).returns([T.nilable(Prism::Node), T.nilable(Prism::Node), T::Array[String]])
    end
    def locate(node, char_position, node_types: [])
      queue = T.let(node.child_nodes.compact, T::Array[T.nilable(Prism::Node)])
      closest = node
      parent = T.let(nil, T.nilable(Prism::Node))
      nesting = T.let([], T::Array[T.any(Prism::ClassNode, Prism::ModuleNode)])

      until queue.empty?
        candidate = queue.shift

        # Skip nil child nodes
        next if candidate.nil?

        # Add the next child_nodes to the queue to be processed. The order here is important! We want to move in the
        # same order as the visiting mechanism, which means searching the child nodes before moving on to the next
        # sibling
        T.unsafe(queue).unshift(*candidate.child_nodes)

        # Skip if the current node doesn't cover the desired position
        loc = candidate.location
        next unless (loc.start_offset...loc.end_offset).cover?(char_position)

        # If the node's start character is already past the position, then we should've found the closest node
        # already
        break if char_position < loc.start_offset

        # If the candidate starts after the end of the previous nesting level, then we've exited that nesting level and
        # need to pop the stack
        previous_level = nesting.last
        nesting.pop if previous_level && loc.start_offset > previous_level.location.end_offset

        # Keep track of the nesting where we found the target. This is used to determine the fully qualified name of the
        # target when it is a constant
        if candidate.is_a?(Prism::ClassNode) || candidate.is_a?(Prism::ModuleNode)
          nesting << candidate
        end

        # If there are node types to filter by, and the current node is not one of those types, then skip it
        next if node_types.any? && node_types.none? { |type| candidate.class == type }

        # If the current node is narrower than or equal to the previous closest node, then it is more precise
        closest_loc = closest.location
        if loc.end_offset - loc.start_offset <= closest_loc.end_offset - closest_loc.start_offset
          parent = closest
          closest = candidate
        end
      end

      [closest, parent, nesting.map { |n| n.constant_path.location.slice }]
    end

    sig { returns(T::Boolean) }
    def sorbet_sigil_is_true_or_higher
      parse_result.magic_comments.any? do |comment|
        comment.key == "typed" && ["true", "strict", "strong"].include?(comment.value)
      end
    end

    sig { returns(T::Boolean) }
    def typechecker_enabled?
      DependencyDetector.instance.typechecker && sorbet_sigil_is_true_or_higher
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
      sig { params(position: T::Hash[Symbol, T.untyped]).returns(Integer) }
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
