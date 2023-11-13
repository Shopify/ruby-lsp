# typed: strict
# frozen_string_literal: true

module RubyLsp
  class ERBDocument < Document
    sig { override.returns(Prism::ParseResult) }
    def parse
      return @parse_result unless @needs_parsing

      @needs_parsing = false
      erb = ERB.new(@source)
      @parse_result = Prism.parse(erb.src)
    end
  end
end
