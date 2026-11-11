# typed: true
# frozen_string_literal: true

require "test_helper"

class LocalVariableFinderTest < Minitest::Test
  def test_groups_reads_and_writes_of_the_same_variable
    source = <<~RUBY
      total = 0
      total += 1
      total ||= 2
      total &&= 3
      a, total = 1, 2
      puts(total)
    RUBY

    assert_occurrences(source, [0, 0], [[0, 0], [1, 0], [2, 0], [3, 0], [4, 3], [5, 5]])
  end

  def test_separates_variables_with_the_same_name_in_different_methods
    source = <<~RUBY
      def foo
        name = 1
        name
      end

      def bar
        name = 2
        name
      end
    RUBY

    assert_occurrences(source, [6, 2], [[6, 2], [7, 2]])
  end

  def test_method_scope_does_not_see_top_level_locals
    source = <<~RUBY
      value = 1

      def foo
        value = 2
        value
      end

      value
    RUBY

    assert_occurrences(source, [0, 0], [[0, 0], [7, 0]])
    assert_occurrences(source, [4, 2], [[3, 2], [4, 2]])
  end

  def test_blocks_see_locals_from_the_enclosing_scope
    source = <<~RUBY
      def foo
        count = 0
        [1, 2].each do |item|
          count += item
          -> { count }
        end
        count
      end
    RUBY

    assert_occurrences(source, [6, 2], [[1, 2], [3, 4], [4, 9], [6, 2]])
    assert_occurrences(source, [3, 13], [[2, 18], [3, 13]])
  end

  def test_block_parameters_and_block_locals_shadow_outer_locals
    source = <<~RUBY
      item = 1
      tmp = 2
      [1].each { |item; tmp| tmp = item }
      item + tmp
    RUBY

    assert_occurrences(source, [0, 0], [[0, 0], [3, 0]])
    assert_occurrences(source, [1, 0], [[1, 0], [3, 7]])
    assert_occurrences(source, [2, 12], [[2, 12], [2, 29]])
    assert_occurrences(source, [2, 23], [[2, 18], [2, 23]])
  end

  def test_locals_first_assigned_in_a_block_are_local_to_the_block
    source = <<~RUBY
      [1].each { result = 1; result }
      [2].each { result = 2; result }
    RUBY

    assert_occurrences(source, [1, 11], [[1, 11], [1, 23]])
  end

  def test_all_parameter_types
    source = <<~RUBY
      def foo(a, b = a, *rest, c:, d: a, **opts, &blk)
        [a, b, rest, c, d, opts, blk]
      end
    RUBY

    assert_occurrences(source, [0, 8], [[0, 8], [0, 15], [0, 32], [1, 3]])
    assert_occurrences(source, [1, 6], [[0, 11], [1, 6]])
    assert_occurrences(source, [1, 9], [[0, 19], [1, 9]])
    assert_occurrences(source, [1, 15], [[0, 25], [1, 15]])
    assert_occurrences(source, [1, 18], [[0, 29], [1, 18]])
    assert_occurrences(source, [1, 21], [[0, 37], [1, 21]])
    assert_occurrences(source, [1, 27], [[0, 44], [1, 27]])
  end

  def test_keyword_parameter_names_exclude_the_colon
    source = <<~RUBY
      def foo(name:)
        name
      end
    RUBY

    variable, _ = find(source, [1, 2])
    occurrence = variable.occurrences.first
    assert_equal("name", occurrence.location.slice)
    assert_equal(:keyword_parameter, occurrence.kind)
  end

  def test_superclass_and_singleton_receivers_belong_to_the_outer_scope
    source = <<~RUBY
      parent = Object
      target = Object.new
      class Foo < parent
        parent = 1
      end
      class << target
      end
      def target.bar; end
    RUBY

    assert_occurrences(source, [0, 0], [[0, 0], [2, 12]])
    assert_occurrences(source, [1, 0], [[1, 0], [5, 9], [7, 4]])
  end

  def test_hash_and_keyword_argument_shorthand
    source = <<~RUBY
      name = "x"
      { name: }
      foo(name:)
    RUBY

    variable, _ = find(source, [0, 0])
    assert_equal([:write, :shorthand, :shorthand], variable.occurrences.map(&:kind))
    assert_equal(["name", "name", "name"], variable.occurrences.map { |o| o.location.slice })
  end

  def test_pattern_matching
    source = <<~RUBY
      expected = 1
      case value
      in { name: } then name
      in [^expected, rest] then rest
      in Integer => number then number
      end
    RUBY

    assert_occurrences(source, [0, 0], [[0, 0], [3, 5]])
    assert_occurrences(source, [2, 18], [[2, 5], [2, 18]])
    assert_occurrences(source, [3, 26], [[3, 15], [3, 26]])
    assert_occurrences(source, [4, 26], [[4, 14], [4, 26]])
  end

  def test_regexp_named_captures
    source = <<~RUBY
      if /(?<year>\\d+)-(?<month>\\d+)/ =~ date
        [year, month]
      end
    RUBY

    variable, _ = find(source, [1, 10])
    assert_equal([[0, 20], [1, 9]], positions(variable))
    assert_equal(:regexp_capture, variable.occurrences.first.kind)
    assert_equal("month", variable.occurrences.first.location.slice)
  end

  def test_regexp_named_captures_repeated_in_the_same_regexp
    source = <<~RUBY
      if /(?<digit>\\d)|(?'digit'[a-f])/ =~ input
        digit
      end
    RUBY

    variable, _ = find(source, [1, 2])
    assert_equal([[0, 7], [0, 20], [1, 2]], positions(variable))
  end

  def test_destructured_block_parameters
    source = <<~RUBY
      pairs.each { |(key, value), index| [key, value, index] }
    RUBY

    assert_occurrences(source, [0, 36], [[0, 15], [0, 36]])
    assert_occurrences(source, [0, 41], [[0, 20], [0, 41]])
    assert_occurrences(source, [0, 48], [[0, 28], [0, 48]])
  end

  def test_for_loops_and_rescue_targets
    source = <<~RUBY
      for item in [1] do item end
      item
      begin
      rescue => error
        error
      end
    RUBY

    assert_occurrences(source, [1, 0], [[0, 4], [0, 19], [1, 0]])
    assert_occurrences(source, [4, 2], [[3, 10], [4, 2]])
  end

  def test_declaration_is_the_first_assignment
    source = <<~RUBY
      def foo(flag)
        if flag
          value = 1
        else
          value = 2
        end
        value
      end
    RUBY

    variable, _ = find(source, [6, 2])
    declaration = variable.declaration #: as !nil
    assert_equal([2, 4], [declaration.location.start_line - 1, declaration.location.start_column])
  end

  def test_ignores_numbered_and_it_parameters
    source = <<~RUBY
      [1].map { _1 }
      [1].map { it }
    RUBY

    assert_nil(find(source, [0, 10]))
    assert_nil(find(source, [1, 10]))
  end

  def test_cursor_at_the_end_of_a_name
    source = <<~RUBY
      foo = 1
      foo
    RUBY

    assert_occurrences(source, [1, 3], [[0, 0], [1, 0]])
  end

  def test_cursor_outside_of_any_local
    source = <<~RUBY
      foo = bar
      Baz
    RUBY

    assert_nil(find(source, [0, 7]))
    assert_nil(find(source, [1, 1]))
  end

  def test_name_in_use
    source = <<~RUBY
      def foo(a)
        b = 1
        [1].each { |c| d = c }
        helper
      end

      def bar
        e = 1
      end
    RUBY

    finder, variable = find_with_finder(source, [1, 2])

    # Parameters and locals of the same method
    assert(finder.name_in_use?(variable, :a))
    # Locals of blocks that can see the variable
    assert(finder.name_in_use?(variable, :c))
    assert(finder.name_in_use?(variable, :d))
    # Method calls that would be shadowed
    assert(finder.name_in_use?(variable, :helper))
    # Locals from a different method are fine
    refute(finder.name_in_use?(variable, :e))
    refute(finder.name_in_use?(variable, :unused))
  end

  def test_name_in_use_checks_enclosing_scopes_of_blocks
    source = <<~RUBY
      outer = 1
      [1].each { inner = 2 }
    RUBY

    finder, variable = find_with_finder(source, [1, 11])
    assert(finder.name_in_use?(variable, :outer))
  end

  def test_multibyte_characters_before_a_local
    source = <<~RUBY
      greeting = "こんにちは"; greeting
    RUBY

    global_state = RubyLsp::GlobalState.new
    global_state.apply_options({ capabilities: { general: { positionEncodings: ["utf-16"] } } })
    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: global_state,
    )
    finder = RubyLsp::Requests::Support::LocalVariableFinder.new(document.ast)
    char_position, _ = document.find_index_by_position({ line: 0, character: 20 })
    variable, _ = finder.variable_at(char_position, document.code_units_cache) #: as !nil

    range = RubyLsp::Requests::Support::LocalVariableFinder.range_for(
      variable.occurrences.fetch(-1).location,
      document.code_units_cache,
    )
    assert_equal({ line: 0, character: 20 }, range.start.to_hash)
    assert_equal({ line: 0, character: 28 }, range.end.to_hash)
  end

  private

  def find(source, position)
    _finder, variable, occurrence = find_with_finder(source, position)
    [variable, occurrence] if variable
  end

  def find_with_finder(source, position)
    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///fake.rb"),
      global_state: RubyLsp::GlobalState.new,
    )
    char_position, _ = document.find_index_by_position({ line: position[0], character: position[1] })
    finder = RubyLsp::Requests::Support::LocalVariableFinder.new(document.ast)
    variable, occurrence = finder.variable_at(char_position, document.code_units_cache)
    [finder, variable, occurrence] if variable
  end

  def positions(variable)
    variable.occurrences.map { |o| [o.location.start_line - 1, o.location.start_column] }
  end

  def assert_occurrences(source, position, expected)
    variable, _ = find(source, position)
    refute_nil(variable, "Expected a local variable at #{position.inspect}")
    assert_equal(expected, positions(variable))
  end
end
