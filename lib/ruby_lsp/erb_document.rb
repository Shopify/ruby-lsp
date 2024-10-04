# typed: strict
# frozen_string_literal: true

module RubyLsp
  class ERBDocument < Document
    extend T::Sig
    extend T::Generic

    sig { returns(String) }
    attr_reader :host_language_source

    ParseResultType = type_member { { fixed: Prism::ParseResult } }

    sig { params(source: String, version: Integer, uri: URI::Generic, encoding: Encoding).void }
    def initialize(source:, version:, uri:, encoding: Encoding::UTF_8)
      # This has to be initialized before calling super because we call `parse` in the parent constructor, which
      # overrides this with the proper virtual host language source
      @host_language_source = T.let("", String)
      super
    end

    sig { override.returns(T::Boolean) }
    def parse!
      return false unless @needs_parsing

      @needs_parsing = false
      scanner = ERBScanner.new(@source)
      scanner.scan
      @host_language_source = scanner.host_language
      # Use partial script to avoid syntax errors in ERB files where keywords may be used without the full context in
      # which they will be evaluated
      @parse_result = Prism.parse(scanner.ruby, partial_script: true)
      true
    end

    sig { override.returns(T::Boolean) }
    def syntax_error?
      @parse_result.failure?
    end

    sig { override.returns(LanguageId) }
    def language_id
      LanguageId::ERB
    end

    sig do
      params(
        position: T::Hash[Symbol, T.untyped],
        node_types: T::Array[T.class_of(Prism::Node)],
      ).returns(NodeContext)
    end
    def locate_node(position, node_types: [])
      RubyDocument.locate(
        @parse_result.value,
        create_scanner.find_char_position(position),
        node_types: node_types,
        encoding: @encoding,
      )
    end

    sig { params(char_position: Integer).returns(T.nilable(T::Boolean)) }
    def inside_host_language?(char_position)
      char = @host_language_source[char_position]
      char && char != " "
    end

    class ERBScanner
      extend T::Sig

      sig { returns(String) }
      attr_reader :ruby, :host_language

      sig { params(source: String).void }
      def initialize(source)
        @source = source
        @host_language = T.let(+"", String)
        @ruby = T.let(+"", String)
        @current_pos = T.let(0, Integer)
        @inside_ruby = T.let(false, T::Boolean)
      end

      sig { void }
      def scan
        while @current_pos < @source.length
          scan_char
          @current_pos += 1
        end
      end

      private

      sig { void }
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
            push_char(T.must(char))
          end
        when "-"
          if @inside_ruby && next_char == "%" &&
              @source[@current_pos + 2] == ">"
            @current_pos += 2
            push_char("   ")
            @inside_ruby = false
          else
            push_char(T.must(char))
          end
        when "%"
          if @inside_ruby && next_char == ">"
            @inside_ruby = false
            @current_pos += 1
            push_char("  ")
          else
            push_char(T.must(char))
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
          push_char(T.must(char))
        end
      end

      sig { params(char: String).void }
      def push_char(char)
        if @inside_ruby
          @ruby << char
          @host_language << " " * char.length
        else
          @ruby << " " * char.length
          @host_language << char
        end
      end

      sig { returns(String) }
      def next_char
        @source[@current_pos + 1] || ""
      end
    end
  end
end
