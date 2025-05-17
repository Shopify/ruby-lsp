# typed: strict
# frozen_string_literal: true

module RubyLsp
  #: [ParseResultType = Prism::ParseLexResult]
  class ERBDocument < Document
    #: String
    attr_reader :host_language_source

    #: (^(Integer arg0) -> Integer | Prism::CodeUnitsCache)
    attr_reader :code_units_cache

    #: (source: String, version: Integer, uri: URI::Generic, global_state: GlobalState) -> void
    def initialize(source:, version:, uri:, global_state:)
      # This has to be initialized before calling super because we call `parse` in the parent constructor, which
      # overrides this with the proper virtual host language source
      @host_language_source = "" #: String
      super
      @code_units_cache =
        @parse_result.code_units_cache(@encoding) #: (^(Integer arg0) -> Integer | Prism::CodeUnitsCache)
    end

    # @override
    #: -> bool
    def parse!
      return false unless @needs_parsing

      @needs_parsing = false
      scanner = ERBScanner.new(@source)
      scanner.scan
      @host_language_source = scanner.host_language
      # Use partial script to avoid syntax errors in ERB files where keywords may be used without the full context in
      # which they will be evaluated
      @parse_result = Prism.parse_lex(scanner.ruby, partial_script: true)
      @code_units_cache = @parse_result.code_units_cache(@encoding)
      true
    end

    #: -> Prism::ProgramNode
    def ast
      @parse_result.value.first
    end

    # @override
    #: -> bool
    def syntax_error?
      @parse_result.failure?
    end

    # @override
    #: -> Symbol
    def language_id
      :erb
    end

    #: (Hash[Symbol, untyped] position, ?node_types: Array[singleton(Prism::Node)]) -> NodeContext
    def locate_node(position, node_types: [])
      char_position, _ = find_index_by_position(position)

      RubyDocument.locate(
        ast,
        char_position,
        code_units_cache: @code_units_cache,
        node_types: node_types,
      )
    end

    #: (Integer char_position) -> bool?
    def inside_host_language?(char_position)
      char = @host_language_source[char_position]
      char && char != " "
    end

    class ERBScanner
      #: String
      attr_reader :ruby, :host_language

      #: (String source) -> void
      def initialize(source)
        @source = source
        @host_language = +"" #: String
        @ruby = +"" #: String
        @current_pos = 0 #: Integer
        @inside_ruby = false #: bool
      end

      #: -> void
      def scan
        while @current_pos < @source.length
          scan_char
          @current_pos += 1
        end
      end

      private

      #: -> void
      def scan_char
        char = @source[@current_pos]

        case char
        when "<"
          if next_char == "%"
            @inside_ruby = true
            @current_pos += 1
            push_char("  ")

            if next_char == "=" && @source[@current_pos + 2] == "="
              @current_pos += 2
              push_char("  ")
            elsif next_char == "=" || next_char == "-"
              @current_pos += 1
              push_char(" ")
            end
          else
            push_char(
              char, #: as !nil
            )
          end
        when "-"
          if @inside_ruby && next_char == "%" &&
              @source[@current_pos + 2] == ">"
            @current_pos += 2
            push_char("   ")
            @inside_ruby = false
          else
            push_char(
              char, #: as !nil
            )
          end
        when "%"
          if @inside_ruby && next_char == ">"
            @inside_ruby = false
            @current_pos += 1
            push_char("  ")
          else
            push_char(
              char, #: as !nil
            )
          end
        when "\r"
          @ruby << char
          @host_language << char

          if next_char == "\n"
            @ruby << next_char
            @host_language << next_char
            @current_pos += 1
          end
        when "\n"
          @ruby << char
          @host_language << char
        else
          push_char(
            char, #: as !nil
          )
        end
      end

      #: (String char) -> void
      def push_char(char)
        if @inside_ruby
          @ruby << char
          @host_language << " " * char.length
        else
          @ruby << " " * char.length
          @host_language << char
        end
      end

      #: -> String
      def next_char
        @source[@current_pos + 1] || ""
      end
    end
  end
end
