# typed: strict
# frozen_string_literal: true

module RubyLsp
  class RubyDocument < Document
    sig { override.returns(Prism::ParseResult) }
    def parse
      return @parse_result unless @needs_parsing

      @needs_parsing = false
      @parse_result = Prism.parse(@source)
    end
  end
end
