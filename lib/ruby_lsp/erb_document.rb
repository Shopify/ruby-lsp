# typed: strict
# frozen_string_literal: true

require "strscan"

module RubyLsp
  class ERBDocument < Document
    sig { override.returns(Prism::ParseResult) }
    def parse
      return @parse_result unless @needs_parsing

      @needs_parsing = false

      @parse_result = Prism.parse(scan(@source))
    end

    private

    sig { params(source: String).returns(String) }
    def scan(source)
      scanner = StringScanner.new(source)
      output = +""

      until scanner.eos?
        non_ruby_code = scanner.scan_until(/<%(-|=)?/)
        break unless non_ruby_code

        output << non_ruby_code.gsub(/[^\n]/, " ")

        ruby_code = scanner.scan_until(/(-)?%>/)
        break unless ruby_code

        output << ruby_code[...-2]
        output << "  "
      end

      warn(output)

      output
    end
  end
end
