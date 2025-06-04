# typed: strict
# frozen_string_literal: true

module RubyLsp
  # @abstract
  #: [ParseResultType]
  class Document
    extend T::Generic

    # This maximum number of characters for providing expensive features, like semantic highlighting and diagnostics.
    # This is the same number used by the TypeScript extension in VS Code
    MAXIMUM_CHARACTERS_FOR_EXPENSIVE_FEATURES = 100_000
    EMPTY_CACHE = Object.new.freeze #: Object

    #: ParseResultType
    attr_reader :parse_result

    #: String
    attr_reader :source

    #: Integer
    attr_reader :version

    #: URI::Generic
    attr_reader :uri

    #: Encoding
    attr_reader :encoding

    #: Edit?
    attr_reader :last_edit

    #: (Interface::SemanticTokens | Object)
    attr_accessor :semantic_tokens

    #: (source: String, version: Integer, uri: URI::Generic, global_state: GlobalState) -> void
    def initialize(source:, version:, uri:, global_state:)
      @source = source
      @version = version
      @global_state = global_state
      @cache = Hash.new(EMPTY_CACHE) #: Hash[String, untyped]
      @semantic_tokens = EMPTY_CACHE #: (Interface::SemanticTokens | Object)
      @encoding = global_state.encoding #: Encoding
      @uri = uri #: URI::Generic
      @needs_parsing = true #: bool
      @last_edit = nil #: Edit?

      # Workaround to be able to type parse_result properly. It is immediately set when invoking parse!
      @parse_result = ( # rubocop:disable Style/RedundantParentheses
        nil #: as untyped
      ) #: ParseResultType

      parse!
    end

    #: (Document[untyped] other) -> bool
    def ==(other)
      self.class == other.class && uri == other.uri && @source == other.source
    end

    # @abstract
    #: -> Symbol
    def language_id; end

    #: [T] (String request_name) { (Document[ParseResultType] document) -> T } -> T
    def cache_fetch(request_name, &block)
      cached = @cache[request_name]
      return cached if cached != EMPTY_CACHE

      result = block.call(self)
      @cache[request_name] = result
      result
    end

    #: [T] (String request_name, T value) -> T
    def cache_set(request_name, value)
      @cache[request_name] = value
    end

    #: (String request_name) -> untyped
    def cache_get(request_name)
      @cache[request_name]
    end

    #: (String request_name) -> void
    def clear_cache(request_name)
      @cache[request_name] = EMPTY_CACHE
    end

    #: (Array[Hash[Symbol, untyped]] edits, version: Integer) -> void
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

      last_edit = edits.last
      return unless last_edit

      last_edit_range = last_edit[:range]

      @last_edit = if last_edit_range[:start] == last_edit_range[:end]
        Insert.new(last_edit_range)
      elsif last_edit[:text].empty?
        Delete.new(last_edit_range)
      else
        Replace.new(last_edit_range)
      end
    end

    # Returns `true` if the document was parsed and `false` if nothing needed parsing
    # @abstract
    #: -> bool
    def parse!; end

    # @abstract
    #: -> bool
    def syntax_error?; end

    #: -> bool
    def past_expensive_limit?
      @source.length > MAXIMUM_CHARACTERS_FOR_EXPENSIVE_FEATURES
    end

    #: (Hash[Symbol, untyped] start_pos, ?Hash[Symbol, untyped]? end_pos) -> [Integer, Integer?]
    def find_index_by_position(start_pos, end_pos = nil)
      @global_state.synchronize do
        scanner = create_scanner
        start_index = scanner.find_char_position(start_pos)
        end_index = scanner.find_char_position(end_pos) if end_pos
        [start_index, end_index]
      end
    end

    private

    #: -> Scanner
    def create_scanner
      Scanner.new(@source, @encoding)
    end

    # @abstract
    class Edit
      #: Hash[Symbol, untyped]
      attr_reader :range

      #: (Hash[Symbol, untyped] range) -> void
      def initialize(range)
        @range = range
      end
    end

    class Insert < Edit; end
    class Replace < Edit; end
    class Delete < Edit; end

    class Scanner
      extend T::Sig

      LINE_BREAK = 0x0A #: Integer
      # After character 0xFFFF, UTF-16 considers characters to have length 2 and we have to account for that
      SURROGATE_PAIR_START = 0xFFFF #: Integer

      #: (String source, Encoding encoding) -> void
      def initialize(source, encoding)
        @current_line = 0 #: Integer
        @pos = 0 #: Integer
        @bytes_or_codepoints = encoding == Encoding::UTF_8 ? source.bytes : source.codepoints #: Array[Integer]
        @encoding = encoding
      end

      # Finds the character index inside the source string for a given line and column
      #: (Hash[Symbol, untyped] position) -> Integer
      def find_char_position(position)
        # Find the character index for the beginning of the requested line
        until @current_line == position[:line]
          @pos += 1 until LINE_BREAK == @bytes_or_codepoints[@pos]
          @pos += 1
          @current_line += 1
        end

        # For UTF-8, the code unit length is the same as bytes, but we want to return the character index
        requested_position = if @encoding == Encoding::UTF_8
          character_offset = 0
          i = @pos

          # Each group of bytes is a character. We advance based on the number of bytes to count how many full
          # characters we have in the requested offset
          while i < @pos + position[:character] && i < @bytes_or_codepoints.length
            byte = @bytes_or_codepoints[i] #: as !nil
            i += if byte < 0x80 # 1-byte character
              1
            elsif byte < 0xE0 # 2-byte character
              2
            elsif byte < 0xF0 # 3-byte character
              3
            else # 4-byte character
              4
            end

            character_offset += 1
          end

          @pos + character_offset
        else
          @pos + position[:character]
        end

        # The final position is the beginning of the line plus the requested column. If the encoding is UTF-16, we also
        # need to adjust for surrogate pairs
        if @encoding == Encoding::UTF_16LE
          requested_position -= utf_16_character_position_correction(@pos, requested_position)
        end

        requested_position
      end

      # Subtract 1 for each character after 0xFFFF in the current line from the column position, so that we hit the
      # right character in the UTF-8 representation
      #: (Integer current_position, Integer requested_position) -> Integer
      def utf_16_character_position_correction(current_position, requested_position)
        utf16_unicode_correction = 0

        until current_position == requested_position
          codepoint = @bytes_or_codepoints[current_position]
          utf16_unicode_correction += 1 if codepoint && codepoint > SURROGATE_PAIR_START

          current_position += 1
        end

        utf16_unicode_correction
      end
    end
  end
end
