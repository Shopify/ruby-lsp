# typed: strict
# frozen_string_literal: true

module RubyLsp
  module ResponseBuilders
    class SemanticHighlighting < ResponseBuilder
      class UndefinedTokenType < StandardError; end

      TOKEN_TYPES = {
        namespace: 0,
        type: 1,
        class: 2,
        enum: 3,
        interface: 4,
        struct: 5,
        typeParameter: 6,
        parameter: 7,
        variable: 8,
        property: 9,
        enumMember: 10,
        event: 11,
        function: 12,
        method: 13,
        macro: 14,
        keyword: 15,
        modifier: 16,
        comment: 17,
        string: 18,
        number: 19,
        regexp: 20,
        operator: 21,
        decorator: 22,
      }.freeze #: Hash[Symbol, Integer]

      TOKEN_MODIFIERS = {
        declaration: 0,
        definition: 1,
        readonly: 2,
        static: 3,
        deprecated: 4,
        abstract: 5,
        async: 6,
        modification: 7,
        documentation: 8,
        default_library: 9,
      }.freeze #: Hash[Symbol, Integer]

      ResponseType = type_member { { fixed: Interface::SemanticTokens } }

      #: ((^(Integer arg0) -> Integer | Prism::CodeUnitsCache) code_units_cache) -> void
      def initialize(code_units_cache)
        super()
        @code_units_cache = code_units_cache
        @stack = [] #: Array[SemanticToken]
      end

      #: (Prism::Location location, Symbol type, ?Array[Symbol] modifiers) -> void
      def add_token(location, type, modifiers = [])
        end_code_unit = location.cached_end_code_units_offset(@code_units_cache)
        length = end_code_unit - location.cached_start_code_units_offset(@code_units_cache)
        modifiers_indices = modifiers.filter_map { |modifier| TOKEN_MODIFIERS[modifier] }
        @stack.push(
          SemanticToken.new(
            start_line: location.start_line,
            start_code_unit_column: location.cached_start_code_units_column(@code_units_cache),
            length: length,
            type: TOKEN_TYPES[type], #: as !nil
            modifier: modifiers_indices,
          ),
        )
      end

      #: (Prism::Location location) -> bool
      def last_token_matches?(location)
        token = @stack.last
        return false unless token

        token.start_line == location.start_line &&
          token.start_code_unit_column == location.cached_start_code_units_column(@code_units_cache)
      end

      #: -> SemanticToken?
      def last
        @stack.last
      end

      # @override
      #: -> Array[SemanticToken]
      def response
        @stack
      end

      class SemanticToken
        #: Integer
        attr_reader :start_line

        #: Integer
        attr_reader :start_code_unit_column

        #: Integer
        attr_reader :length

        #: Integer
        attr_reader :type

        #: Array[Integer]
        attr_reader :modifier

        #: (start_line: Integer, start_code_unit_column: Integer, length: Integer, type: Integer, modifier: Array[Integer]) -> void
        def initialize(start_line:, start_code_unit_column:, length:, type:, modifier:)
          @start_line = start_line
          @start_code_unit_column = start_code_unit_column
          @length = length
          @type = type
          @modifier = modifier
        end

        #: (Symbol type_symbol) -> void
        def replace_type(type_symbol)
          type_int = TOKEN_TYPES[type_symbol]
          raise UndefinedTokenType, "Undefined token type: #{type_symbol}" unless type_int

          @type = type_int
        end

        #: (Array[Symbol] modifier_symbols) -> void
        def replace_modifier(modifier_symbols)
          @modifier = modifier_symbols.filter_map do |modifier_symbol|
            modifier_index = TOKEN_MODIFIERS[modifier_symbol]
            raise UndefinedTokenType, "Undefined token modifier: #{modifier_symbol}" unless modifier_index

            modifier_index
          end
        end
      end

      class SemanticTokenEncoder
        #: -> void
        def initialize
          @current_row = 0 #: Integer
          @current_column = 0 #: Integer
        end

        #: (Array[SemanticToken] tokens) -> Array[Integer]
        def encode(tokens)
          sorted_tokens = tokens.sort_by.with_index do |token, index|
            # Enumerable#sort_by is not deterministic when the compared values are equal.
            # When that happens, we need to use the index as a tie breaker to ensure
            # that the order of the tokens is always the same.
            [token.start_line, token.start_code_unit_column, index]
          end

          delta = sorted_tokens.flat_map do |token|
            compute_delta(token)
          end

          delta
        end

        # The delta array is computed according to the LSP specification:
        # > The protocol for the token format relative uses relative
        # > positions, because most tokens remain stable relative to
        # > each other when edits are made in a file. This simplifies
        # > the computation of a delta if a server supports it. So each
        # > token is represented using 5 integers.

        # For more information on how each number is calculated, read:
        # https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_semanticTokens
        #: (SemanticToken token) -> Array[Integer]
        def compute_delta(token)
          row = token.start_line - 1
          column = token.start_code_unit_column

          begin
            delta_line = row - @current_row

            delta_column = column
            delta_column -= @current_column if delta_line == 0

            [delta_line, delta_column, token.length, token.type, encode_modifiers(token.modifier)]
          ensure
            @current_row = row
            @current_column = column
          end
        end

        # Encode an array of modifiers to positions onto a bit flag
        # For example, [:default_library] will be encoded as
        # 0b1000000000, as :default_library is the 10th bit according
        # to the token modifiers index map.
        #: (Array[Integer] modifiers) -> Integer
        def encode_modifiers(modifiers)
          modifiers.inject(0) do |encoded_modifiers, modifier|
            encoded_modifiers | (1 << modifier)
          end
        end
      end
    end
  end
end
