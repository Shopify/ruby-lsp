# typed: strict
# frozen_string_literal: true

module RubyLsp
  #: [ParseResultType = Array[RBS::AST::Declarations::Base]]
  class RBSDocument < Document
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
    #: -> Symbol
    def language_id
      :rbs
    end
  end
end
