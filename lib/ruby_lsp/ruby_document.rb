# typed: strict
# frozen_string_literal: true

module RubyLsp
  class RubyDocument < Document
    class SorbetLevel < T::Enum
      enums do
        None = new("none")
        Ignore = new("ignore")
        False = new("false")
        True = new("true")
        Strict = new("strict")
      end
    end

    sig { override.returns(Prism::ParseResult) }
    def parse
      return @parse_result unless @needs_parsing

      @needs_parsing = false
      @parse_result = Prism.parse(@source)
    end

    sig { override.returns(T::Boolean) }
    def syntax_error?
      @parse_result.failure?
    end

    sig { override.returns(LanguageId) }
    def language_id
      LanguageId::Ruby
    end

    sig { returns(SorbetLevel) }
    def sorbet_level
      sigil = parse_result.magic_comments.find do |comment|
        comment.key == "typed"
      end&.value

      case sigil
      when "ignore"
        SorbetLevel::Ignore
      when "false"
        SorbetLevel::False
      when "true"
        SorbetLevel::True
      when "strict", "strong"
        SorbetLevel::Strict
      else
        SorbetLevel::None
      end
    end
  end
end
