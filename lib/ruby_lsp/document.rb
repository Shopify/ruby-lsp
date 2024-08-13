# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Document
    class LanguageId < T::Enum
      enums do
        Ruby = new("ruby")
        ERB = new("erb")
      end
    end

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

    sig { returns(Encoding) }
    attr_reader :encoding

    sig { params(source: String, version: Integer, uri: URI::Generic, encoding: Encoding).void }
    def initialize(source:, version:, uri:, encoding: Encoding::UTF_8)
      @cache = T.let({}, T::Hash[String, T.untyped])
      @encoding = T.let(encoding, Encoding)
      @source = T.let(source, String)
      @version = T.let(version, Integer)
      @uri = T.let(uri, URI::Generic)
      @needs_parsing = T.let(true, T::Boolean)
      @parse_result = T.let(parse, Prism::ParseResult)
    end

    sig { params(other: Document).returns(T::Boolean) }
    def ==(other)
      self.class == other.class && uri == other.uri && @source == other.source
    end

    sig { abstract.returns(LanguageId) }
    def language_id; end

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

    sig { abstract.returns(T::Boolean) }
    def syntax_error?; end

    sig { returns(Scanner) }
    def create_scanner
      Scanner.new(@source, @encoding)
    end

    sig do
      params(
        position: T::Hash[Symbol, T.untyped],
        node_types: T::Array[T.class_of(Prism::Node)],
      ).returns(NodeContext)
    end
    def locate_node(position, node_types: [])
      locate(@parse_result.value, create_scanner.find_char_position(position), node_types: node_types)
    end

    sig do
      params(
        node: Prism::Node,
        char_position: Integer,
        node_types: T::Array[T.class_of(Prism::Node)],
      ).returns(NodeContext)
    end
    def locate(node, char_position, node_types: [])
      queue = T.let(node.child_nodes.compact, T::Array[T.nilable(Prism::Node)])
      closest = node
      parent = T.let(nil, T.nilable(Prism::Node))
      nesting_nodes = T.let(
        [],
        T::Array[T.any(
          Prism::ClassNode,
          Prism::ModuleNode,
          Prism::SingletonClassNode,
          Prism::DefNode,
          Prism::BlockNode,
          Prism::LambdaNode,
          Prism::ProgramNode,
        )],
      )

      nesting_nodes << node if node.is_a?(Prism::ProgramNode)
      call_node = T.let(nil, T.nilable(Prism::CallNode))

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
        previous_level = nesting_nodes.last
        nesting_nodes.pop if previous_level && loc.start_offset > previous_level.location.end_offset

        # Keep track of the nesting where we found the target. This is used to determine the fully qualified name of the
        # target when it is a constant
        case candidate
        when Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode, Prism::DefNode, Prism::BlockNode,
          Prism::LambdaNode
          nesting_nodes << candidate
        end

        if candidate.is_a?(Prism::CallNode)
          arg_loc = candidate.arguments&.location
          blk_loc = candidate.block&.location
          if (arg_loc && (arg_loc.start_offset...arg_loc.end_offset).cover?(char_position)) ||
              (blk_loc && (blk_loc.start_offset...blk_loc.end_offset).cover?(char_position))
            call_node = candidate
          end
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

      # When targeting the constant part of a class/module definition, we do not want the nesting to be duplicated. That
      # is, when targeting Bar in the following example:
      #
      # ```ruby
      #   class Foo::Bar; end
      # ```
      # The correct target is `Foo::Bar` with an empty nesting. `Foo::Bar` should not appear in the nesting stack, even
      # though the class/module node does indeed enclose the target, because it would lead to incorrect behavior
      if closest.is_a?(Prism::ConstantReadNode) || closest.is_a?(Prism::ConstantPathNode)
        last_level = nesting_nodes.last

        if (last_level.is_a?(Prism::ModuleNode) || last_level.is_a?(Prism::ClassNode)) &&
            last_level.constant_path == closest
          nesting_nodes.pop
        end
      end

      NodeContext.new(closest, parent, nesting_nodes, call_node)
    end

    class Scanner
      extend T::Sig

      LINE_BREAK = T.let(0x0A, Integer)
      # After character 0xFFFF, UTF-16 considers characters to have length 2 and we have to account for that
      SURROGATE_PAIR_START = T.let(0xFFFF, Integer)

      sig { params(source: String, encoding: Encoding).void }
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

        if @encoding == Encoding::UTF_16LE
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
