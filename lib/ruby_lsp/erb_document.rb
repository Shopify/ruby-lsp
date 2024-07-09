# typed: strict
# frozen_string_literal: true

module RubyLsp
  class ERBDocument < Document
    extend T::Sig

    sig { override.returns(Prism::ParseResult) }
    def parse
      return @parse_result unless @needs_parsing

      @needs_parsing = false
      scanner = ERBScanner.new(@source)
      scanner.scan
      @parse_result = Prism.parse(scanner.ruby)
    end

    sig { override.returns(T::Boolean) }
    def syntax_error?
      @parse_result.failure?
    end

    sig { override.returns(LanguageId) }
    def language_id
      LanguageId::ERB
    end

    class ERBScanner
      extend T::Sig

      sig { returns(String) }
      attr_reader :ruby, :html

      sig { params(source: String).void }
      def initialize(source)
        @source = source
        @html = T.let(+"", String)
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
          @html << char

          if next_char == "\n"
            @ruby << next_char
            @html << next_char
            @current_pos += 1
          end
        when "\n"
          @ruby << char
          @html << char
        else
          push_char(T.must(char))
        end
      end

      sig { params(char: String).void }
      def push_char(char)
        if @inside_ruby
          @ruby << char
          @html << " " * char.length
        else
          @ruby << " " * char.length
          @html << char
        end
      end

      sig { returns(String) }
      def next_char
        @source[@current_pos + 1] || ""
      end
    end
  end
end
