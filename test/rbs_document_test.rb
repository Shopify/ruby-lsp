# typed: true
# frozen_string_literal: true

require "test_helper"

class RBSDocumentTest < Minitest::Test
  def test_parse_result_is_array_of_declarations
    document = RubyLsp::RBSDocument.new(source: <<~RBS, version: 1, uri: URI("file:///foo.rbs"))
      class Foo
        def bar: () -> void
      end
    RBS

    refute_predicate(document, :syntax_error?)
    assert_equal(:Foo, T.cast(document.parse_result[0], RBS::AST::Declarations::Class).name.name)
  end

  def test_parsing_remembers_syntax_errors
    # The syntax error is that `-` should be `->`
    document = RubyLsp::RBSDocument.new(source: +<<~RBS, version: 1, uri: URI("file:///foo.rbs"))
      class Foo
        def bar: () - void
      end
    RBS

    assert_predicate(document, :syntax_error?)

    document.push_edits(
      [{ range: { start: { line: 1, character: 15 }, end: { line: 1, character: 15 } }, text: ">" }],
      version: 2,
    )
    document.parse
    refute_predicate(document, :syntax_error?)
  end
end
