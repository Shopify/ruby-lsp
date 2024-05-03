# typed: true
# frozen_string_literal: true

begin
  gem("rubocop", ">= 1.63.0")
rescue LoadError
  $stderr.puts("AST translation turned off because RuboCop >= 1.63.0 is required")
  return
end

require "prism/translation/parser/rubocop"

# Processed Source patch so that we can pass the existing AST to RuboCop without having to re-parse files a second time
module ProcessedSourcePatch
  extend T::Sig

  sig do
    params(
      source: String,
      ruby_version: Float,
      path: T.nilable(String),
      parser_engine: Symbol,
      prism_result: T.nilable(Prism::ParseLexResult),
    ).void
  end
  def initialize(source, ruby_version, path = nil, parser_engine: :parser_whitequark, prism_result: nil)
    @prism_result = prism_result

    # Invoking super will end up invoking our patched version of tokenize, which avoids re-parsing the file
    super(source, ruby_version, path, parser_engine: parser_engine)
  end

  sig { params(parser: T.untyped).returns(T::Array[T.untyped]) }
  def tokenize(parser)
    begin
      # This is where we need to pass the existing result to prevent a re-parse
      ast, comments, tokens = parser.tokenize(@buffer, parse_result: @prism_result)

      ast ||= nil
    rescue Parser::SyntaxError
      comments = []
      tokens = []
    end

    ast&.complete!
    tokens.map! { |t| RuboCop::AST::Token.from_parser_token(t) }

    [ast, comments, tokens]
  end

  RuboCop::AST::ProcessedSource.prepend(self)
end

# This patch allows Prism's translation parser to accept an existing AST in `tokenize`. This doesn't match the original
# signature of RuboCop itself, but there's no other way to allow reusing the AST
module TranslatorPatch
  extend T::Sig
  extend T::Helpers

  requires_ancestor { Prism::Translation::Parser }

  sig do
    params(
      source_buffer: ::Parser::Source::Buffer,
      recover: T::Boolean,
      parse_result: T.nilable(Prism::ParseLexResult),
    ).returns(T::Array[T.untyped])
  end
  def tokenize(source_buffer, recover = false, parse_result: nil)
    @source_buffer = source_buffer
    source = source_buffer.source

    offset_cache = build_offset_cache(source)
    result = if @prism_result
      @prism_result
    else
      begin
        unwrap(
          Prism.parse_lex(source, filepath: source_buffer.name, version: convert_for_prism(version)),
          offset_cache,
        )
      rescue ::Parser::SyntaxError
        raise unless recover
      end
    end

    program, tokens = result.value
    ast = build_ast(program, offset_cache) if result.success?

    [
      ast,
      build_comments(result.comments, offset_cache),
      build_tokens(tokens, offset_cache),
    ]
  ensure
    @source_buffer = nil
  end

  Prism::Translation::Parser.prepend(self)
end
