# typed: strict
# frozen_string_literal: true

module RubyLsp
  class Document
    class LanguageId < T::Enum
      enums do
        Ruby = new("ruby")
        ERB = new("erb")
        RBS = new("rbs")
      end
    end

    extend T::Sig
    extend T::Helpers
    extend T::Generic

    class LocationNotFoundError < StandardError; end
    ParseResultType = type_member

    # This maximum number of characters for providing expensive features, like semantic highlighting and diagnostics.
    # This is the same number used by the TypeScript extension in VS Code
    MAXIMUM_CHARACTERS_FOR_EXPENSIVE_FEATURES = 100_000
    EMPTY_CACHE = Object.new.freeze #: Object

    abstract!

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
      @parse_result = T.unsafe(nil) #: ParseResultType
      @last_edit = nil #: Edit?
      parse!
    end

    #: (Document[untyped] other) -> bool
    def ==(other)
      self.class == other.class && uri == other.uri && @source == other.source
    end

    sig { abstract.returns(LanguageId) }
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
    sig { abstract.returns(T::Boolean) }
    def parse!; end

    sig { abstract.returns(T::Boolean) }
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

    class Edit
      extend T::Sig
      extend T::Helpers

      abstract!

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
        @source = source.codepoints #: Array[Integer]
        @encoding = encoding
      end

      # Finds the character index inside the source string for a given line and column
      #: (Hash[Symbol, untyped] position) -> Integer
      def find_char_position(position)
        # Find the character index for the beginning of the requested line
        until @current_line == position[:line]
          until LINE_BREAK == @source[@pos]
            @pos += 1

            if @pos >= @source.length
              # Pack the code points back into the original string to provide context in the error message
              raise LocationNotFoundError, "Requested position: #{position}\nSource:\n\n#{@source.pack("U*")}"
            end
          end

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
      #: (Integer current_position, Integer requested_position) -> Integer
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
