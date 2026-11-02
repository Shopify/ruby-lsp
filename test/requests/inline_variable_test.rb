# typed: true
# frozen_string_literal: true

require "test_helper"

class InlineVariableTest < Minitest::Test
  def test_keeps_the_grouping_of_operators
    assert_inlined(<<~RUBY, <<~EXPECTED)
      a = 2 ** 3
      b = a ** 2
      c = 2 ** a
      d = 1 - a
    RUBY
      b = (2 ** 3) ** 2
      c = 2 ** 2 ** 3
      d = 1 - 2 ** 3
    EXPECTED
  end

  def test_wraps_negative_numbers_that_would_bind_differently
    assert_inlined(<<~RUBY, <<~EXPECTED)
      a = -1
      b = a ** 2
      c = a.abs
      d = 3 - a
    RUBY
      b = (-1) ** 2
      c = (-1).abs
      d = 3 - -1
    EXPECTED
  end

  def test_wraps_values_used_as_receivers
    assert_inlined(<<~RUBY, <<~EXPECTED)
      a = 1..3
      puts a.to_a
    RUBY
      puts (1..3).to_a
    EXPECTED
  end

  def test_wraps_hashes_passed_without_parentheses
    assert_inlined(<<~RUBY, <<~EXPECTED)
      a = { key: 1 }
      puts a
    RUBY
      puts ({ key: 1 })
    EXPECTED
  end

  def test_wraps_keyword_operators
    assert_inlined(<<~RUBY, <<~EXPECTED)
      a = (x and y)
      b = a
    RUBY
      b = (x and y)
    EXPECTED
  end

  def test_inlines_into_a_condition
    assert_inlined(<<~RUBY, <<~EXPECTED)
      ready = check_status
      if ready
        start
      end
    RUBY
      if check_status
        start
      end
    EXPECTED
  end

  def test_inlines_into_blocks_when_the_value_has_no_method_calls
    assert_inlined(<<~RUBY, <<~EXPECTED)
      limit = 10
      items.each { |item| puts item if item > limit }
    RUBY
      items.each { |item| puts item if item > 10 }
    EXPECTED
  end

  def test_ignores_block_parameters_with_the_same_name
    assert_inlined(<<~RUBY, <<~EXPECTED)
      a = 1
      [2].each { |a| puts a }
      puts a
    RUBY
      [2].each { |a| puts a }
      puts 1
    EXPECTED
  end

  def test_works_from_a_read
    assert_inlined(<<~RUBY, <<~EXPECTED, line: 1, character: 5)
      a = 1
      puts a
    RUBY
      puts 1
    EXPECTED
  end

  def test_is_not_offered_away_from_a_local_variable
    assert_not_offered("a = 1\nputs a\n", line: 0, character: 4)
    assert_not_offered("@a = 1\nputs @a\n", line: 0, character: 0)
  end

  def test_refuses_variables_assigned_more_than_once
    assert_refused("Only a variable assigned once can be inlined", "a = 1\na = 2\nputs a\n")
    assert_refused("Only a variable assigned once can be inlined", "a = 1\na += 2\nputs a\n")
    assert_refused("Only a variable assigned once can be inlined", "def foo(a)\n  a = 1\n  puts a\nend\n", line: 1, character: 2)
  end

  def test_refuses_assignments_inside_expressions
    assert_refused(
      "Only a variable assigned in a statement of its own can be inlined",
      "foo(a = 1)\nputs a\n",
      character: 4,
    )
  end

  def test_refuses_reads_the_assignment_may_not_reach
    assert_refused("The variable is read where its assignment may not have run", "a = 1 if cond\nputs a\n")
  end

  def test_refuses_variables_that_are_never_read
    assert_refused("The variable is never read", "a = 1\n")
  end

  def test_refuses_values_with_heredocs
    assert_refused("Values with heredocs can't be inlined", "a = <<~TEXT\n  hi\nTEXT\nputs a\n")
  end

  def test_refuses_to_change_how_often_method_calls_run
    message = "A value that calls methods or builds objects can only be inlined once, into the next statement"
    assert_refused(message, "a = compute\nputs a\nputs a\n")
    assert_refused(message, "a = compute\nlog\nputs a\n")
    assert_refused(message, "a = compute\nitems.each { puts a }\n")
    assert_refused(message, "a = compute\nflag && use(a)\n")
  end

  def test_refuses_values_whose_variables_change_before_the_read
    message = "A variable the value uses is reassigned before the value is read"
    assert_refused(message, "x = 1\na = x\nx = 2\nputs a\n", line: 1)
    assert_refused(message, "x = 1\na = x\ncallback = -> { a }\nx = 2\n", line: 1)
  end

  private

  def assert_inlined(source, expected, line: 0, character: 0)
    document, range = document_and_range(source, line, character)
    result = RubyLsp::Requests::CodeActionResolve.new(document, RubyLsp::GlobalState.new, code_action(range)).perform

    assert_equal(expected, apply(source, result.edit.document_changes.first.edits))
  end

  def assert_refused(message, source, line: 0, character: 0)
    document, range = document_and_range(source, line, character)
    error = assert_raises(RubyLsp::Requests::CodeActionResolve::InvalidTargetRangeError) do
      RubyLsp::Requests::CodeActionResolve.new(document, RubyLsp::GlobalState.new, code_action(range)).perform
    end

    assert_equal(message, error.message)
  end

  def assert_not_offered(source, line:, character:)
    document, range = document_and_range(source, line, character)
    actions = RubyLsp::Requests::CodeActions.new(document, range, { diagnostics: [] }).perform || []
    titles = actions.map(&:title)

    refute_includes(titles, RubyLsp::Requests::CodeActions::INLINE_VARIABLE_TITLE)
  end

  def document_and_range(source, line, character)
    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: RubyLsp::GlobalState.new,
    )
    position = { line: line, character: character }
    [document, { start: position, end: position }]
  end

  def code_action(range)
    {
      title: RubyLsp::Requests::CodeActions::INLINE_VARIABLE_TITLE,
      data: { range: range, uri: "file:///fake.rb" },
    }
  end

  def apply(source, edits)
    lines = source.lines
    offset = ->(position) { lines.first(position.line).sum(&:bytesize) + position.character }
    result = source.dup

    edits.sort_by { |edit| -offset.call(edit.range.start) }.each do |edit|
      result[offset.call(edit.range.start)...offset.call(edit.range.end)] = edit.new_text
    end

    result
  end
end
