# typed: strict
# frozen_string_literal: true

module RubyLsp
  class RBSDocument < Document
    extend T::Generic

    ParseResultType = type_member { { fixed: T::Array[RBS::AST::Declarations::Base] } }

    #: (source: String, version: Integer, uri: URI::Generic, global_state: GlobalState) -> void
    def initialize(source:, version:, uri:, global_state:)
      @syntax_error = false #: bool
      super
    end

    # @override
    #: -> bool
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

    # @override
    #: -> bool
    def syntax_error?
      @syntax_error
    end

    # @override
    #: -> LanguageId
    def language_id
      LanguageId::RBS
    end
  end
end
