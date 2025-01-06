# typed: strict
# frozen_string_literal: true

module RubyLsp
  class RBSDocument < Document
    extend T::Sig
    extend T::Generic

    ParseResultType = type_member { { fixed: T::Array[RBS::AST::Declarations::Base] } }

    sig { params(source: String, version: Integer, uri: URI::Generic, global_state: GlobalState).void }
    def initialize(source:, version:, uri:, global_state:)
      @syntax_error = T.let(false, T::Boolean)
      super
    end

    sig { override.returns(T::Boolean) }
    def parse!
      return false unless @needs_parsing

      @needs_parsing = false

      _, _, declarations = RBS::Parser.parse_signature(@source)
      @syntax_error = false
      @parse_result = declarations
      true
    rescue RBS::ParsingError
      @syntax_error = true
      true
    end

    sig { override.returns(T::Boolean) }
    def syntax_error?
      @syntax_error
    end

    sig { override.returns(LanguageId) }
    def language_id
      LanguageId::RBS
    end
  end
end
