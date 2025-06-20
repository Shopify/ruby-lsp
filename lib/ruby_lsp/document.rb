# typed: strict
# frozen_string_literal: true

module RubyLsp
  # @abstract
  #: [ParseResultType]
  class Document
    class InvalidLocationError < StandardError; end

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
    def language_id
      raise AbstractMethodInvokedError
    end

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
    def parse!
      raise AbstractMethodInvokedError
    end

    # @abstract
    #: -> bool
    def syntax_error?
      raise AbstractMethodInvokedError
    end

    #: -> bool
    def past_expensive_limit?
      @source.length > MAXIMUM_CHARACTERS_FOR_EXPENSIVE_FEATURES
    end

    #: (Hash[Symbol, untyped] start_pos, ?Hash[Symbol, untyped]? end_pos) -> [Integer, Integer?]
    def find_index_by_position(start_pos, end_pos = nil)
      scanner = create_scanner
      start_index = scanner.find_char_position(start_pos)
      end_index = scanner.find_char_position(end_pos) if end_pos
      [start_index, end_index]
    end

    private

    #: -> Scanner
    def create_scanner
      case @encoding
      when Encoding::UTF_8
        Utf8Scanner.new(@source)
      when Encoding::UTF_16LE
        Utf16Scanner.new(@source)
      else
        Utf32Scanner.new(@source)
      end
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

    # Parent class for all position scanners. Scanners are used to translate a position given by the editor into a
    # string index that we can use to find the right place in the document source. The logic for finding the correct
    # index depends on the encoding negotiated with the editor, so we have different subclasses for each encoding.
    # See https://microsoft.github.io/language-server-protocol/specification/#positionEncodingKind for more information
    # @abstract
    class Scanner
      LINE_BREAK = 0x0A #: Integer
      # After character 0xFFFF, UTF-16 considers characters to have length 2 and we have to account for that
      SURROGATE_PAIR_START = 0xFFFF #: Integer

      #: -> void
      def initialize
        @current_line = 0 #: Integer
        @pos = 0 #: Integer
      end

      # Finds the character index inside the source string for a given line and column. This method always returns the
      # character index regardless of whether we are searching positions based on bytes, code units, or codepoints.
      # @abstract
      #: (Hash[Symbol, untyped] position) -> Integer
      def find_char_position(position)
        raise AbstractMethodInvokedError
      end
    end

    # For the UTF-8 encoding, positions correspond to bytes
    class Utf8Scanner < Scanner
      #: (String source) -> void
      def initialize(source)
        super()
        @bytes = source.bytes #: Array[Integer]
        @character_length = 0 #: Integer
      end

      # @override
      #: (Hash[Symbol, untyped] position) -> Integer
      def find_char_position(position)
        # Each group of bytes is a character. We advance based on the number of bytes to count how many full characters
        # we have in the requested offset
        until @current_line == position[:line]
          byte = @bytes[@pos] #: Integer?
          raise InvalidLocationError unless byte

          until LINE_BREAK == byte
            @pos += character_byte_length(byte)
            @character_length += 1
            byte = @bytes[@pos]
            raise InvalidLocationError unless byte
          end

          @pos += 1
          @character_length += 1
          @current_line += 1
        end

        # @character_length has the number of characters until the beginning of the line. We don't accumulate on it for
        # the character part because locating the same position twice must return the same value
        line_byte_offset = 0
        line_characters = 0

        while line_byte_offset < position[:character]
          byte = @bytes[@pos + line_byte_offset] #: Integer?
          raise InvalidLocationError unless byte

          line_byte_offset += character_byte_length(byte)
          line_characters += 1
        end

        @character_length + line_characters
      end

      private

      #: (Integer) -> Integer
      def character_byte_length(byte)
        if byte < 0x80 # 1-byte character
          1
        elsif byte < 0xE0 # 2-byte character
          2
        elsif byte < 0xF0 # 3-byte character
          3
        else # 4-byte character
          4
        end
      end
    end

    # For the UTF-16 encoding, positions correspond to UTF-16 code units, which count characters beyond the surrogate
    # pair as length 2
    class Utf16Scanner < Scanner
      #: (String) -> void
      def initialize(source)
        super()
        @codepoints = source.codepoints #: Array[Integer]
      end

      # @override
      #: (Hash[Symbol, untyped] position) -> Integer
      def find_char_position(position)
        # Find the character index for the beginning of the requested line
        until @current_line == position[:line]
          codepoint = @codepoints[@pos] #: Integer?
          raise InvalidLocationError unless codepoint

          until LINE_BREAK == @codepoints[@pos]
            @pos += 1
            codepoint = @codepoints[@pos] #: Integer?
            raise InvalidLocationError unless codepoint
          end

          @pos += 1
          @current_line += 1
        end

        # The final position is the beginning of the line plus the requested column. If the encoding is UTF-16, we also
        # need to adjust for surrogate pairs
        line_characters = 0
        line_code_units = 0

        while line_code_units < position[:character]
          code_point = @codepoints[@pos + line_characters]
          raise InvalidLocationError unless code_point

          line_code_units += if code_point > SURROGATE_PAIR_START
            2 # Surrogate pair, so we skip the next code unit
          else
            1 # Single code unit character
          end

          line_characters += 1
        end

        @pos + line_characters
      end
    end

    # For the UTF-32 encoding, positions correspond directly to codepoints
    class Utf32Scanner < Scanner
      #: (String) -> void
      def initialize(source)
        super()
        @codepoints = source.codepoints #: Array[Integer]
      end

      # @override
      #: (Hash[Symbol, untyped] position) -> Integer
      def find_char_position(position)
        # Find the character index for the beginning of the requested line
        until @current_line == position[:line]
          codepoint = @codepoints[@pos] #: Integer?
          raise InvalidLocationError unless codepoint

          until LINE_BREAK == @codepoints[@pos]
            @pos += 1
            codepoint = @codepoints[@pos] #: Integer?
            raise InvalidLocationError unless codepoint
          end

          @pos += 1
          @current_line += 1
        end

        @pos + position[:character]
      end
    end
  end
end
