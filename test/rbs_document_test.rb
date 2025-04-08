# typed: true
# frozen_string_literal: true

require "test_helper"

class RBSDocumentTest < Minitest::Test
  def setup
    @global_state = RubyLsp::GlobalState.new
  end

  def test_parse_result_is_array_of_declarations
    source = <<~RBS
      class Foo
        def bar: () -> void
      end
    RBS

    document = RubyLsp::RBSDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///foo.rbs"),
      global_state: @global_state,
    )

    refute_predicate(document, :syntax_error?)
    assert_equal(
      :Foo,
      document
        .parse_result[0] #: as RBS::AST::Declarations::Class
        .name
        .name,
    )
  end

  def test_parsing_remembers_syntax_errors
    # The syntax error is that `-` should be `->`
    source = +<<~RBS
      class Foo
        def bar: () - void
      end
    RBS
    document = RubyLsp::RBSDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///foo.rbs"),
      global_state: @global_state,
    )

    assert_predicate(document, :syntax_error?)

    document.push_edits(
      [{ range: { start: { line: 1, character: 15 }, end: { line: 1, character: 15 } }, text: ">" }],
      version: 2,
    )
    document.parse!
    refute_predicate(document, :syntax_error?)
  end
end
