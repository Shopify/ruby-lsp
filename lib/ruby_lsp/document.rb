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
    EMPTY_CACHE = T.let(Object.new.freeze, Object)

    abstract!

    sig { returns(ParseResultType) }
    attr_reader :parse_result

    sig { returns(String) }
    attr_reader :source

    sig { returns(Integer) }
    attr_reader :version

    sig { returns(URI::Generic) }
    attr_reader :uri

    sig { returns(Encoding) }
    attr_reader :encoding

    sig { returns(T.nilable(Edit)) }
    attr_reader :last_edit

    sig { returns(T.any(Interface::SemanticTokens, Object)) }
    attr_accessor :semantic_tokens

    sig { params(source: String, version: Integer, uri: URI::Generic, global_state: GlobalState).void }
    def initialize(source:, version:, uri:, global_state:)
      @source = source
      @version = version
      @global_state = global_state
      @cache = T.let(Hash.new(EMPTY_CACHE), T::Hash[String, T.untyped])
      @semantic_tokens = T.let(EMPTY_CACHE, T.any(Interface::SemanticTokens, Object))
      @encoding = T.let(global_state.encoding, Encoding)
      @uri = T.let(uri, URI::Generic)
      @needs_parsing = T.let(true, T::Boolean)
      @parse_result = T.let(T.unsafe(nil), ParseResultType)
      @last_edit = T.let(nil, T.nilable(Edit))
      parse!
    end

    sig { params(other: Document[T.untyped]).returns(T::Boolean) }
    def ==(other)
      self.class == other.class && uri == other.uri && @source == other.source
    end

    sig { abstract.returns(LanguageId) }
    def language_id; end

    sig do
      type_parameters(:T)
        .params(
          request_name: String,
          block: T.proc.params(document: Document[ParseResultType]).returns(T.type_parameter(:T)),
        ).returns(T.type_parameter(:T))
    end
    def cache_fetch(request_name, &block)
      cached = @cache[request_name]
      return cached if cached != EMPTY_CACHE

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

    sig { returns(T::Boolean) }
    def past_expensive_limit?
      @source.length > MAXIMUM_CHARACTERS_FOR_EXPENSIVE_FEATURES
    end

    sig do
      params(
        start_pos: T::Hash[Symbol, T.untyped],
        end_pos: T.nilable(T::Hash[Symbol, T.untyped]),
      ).returns([Integer, T.nilable(Integer)])
    end
    def find_index_by_position(start_pos, end_pos = nil)
      @global_state.synchronize do
        scanner = create_scanner
        start_index = scanner.find_char_position(start_pos)
        end_index = scanner.find_char_position(end_pos) if end_pos
        [start_index, end_index]
      end
    end

    private

    sig { returns(Scanner) }
    def create_scanner
      Scanner.new(@source, @encoding)
    end

    class Edit
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :range

      sig { params(range: T::Hash[Symbol, T.untyped]).void }
      def initialize(range)
        @range = range
      end
    end

    class Insert < Edit; end
    class Replace < Edit; end
    class Delete < Edit; end

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
