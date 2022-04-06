# frozen_string_literal: true

require "test_helper"

class FoldingRangesTest < Minitest::Test
  def test_folding_method_definitions
    ranges = [{ startLine: 0, endLine: 3, kind: "region" }]
    assert_ranges(<<~RUBY, ranges)
      def foo
        a = 2
        puts "a"
      end
    RUBY
  end

  def test_folding_long_params_method_definitions
    ranges = [{ startLine: 3, endLine: 6, kind: "region" }]
    assert_ranges(<<~RUBY, ranges)
      def foo(
        a,
        b
      )
        a = 2
        puts "a"
      end
    RUBY
  end

  def test_folding_singleton_method_definitions
    ranges = [{ startLine: 0, endLine: 3, kind: "region" }]
    assert_ranges(<<~RUBY, ranges)
      def self.foo
        a = 2
        puts "a"
      end
    RUBY
  end

  def test_folding_long_params_singleton_method_definitions
    ranges = [{ startLine: 3, endLine: 6, kind: "region" }]
    assert_ranges(<<~RUBY, ranges)
      def self.foo(
        a,
        b
      )
        a = 2
        puts "a"
      end
    RUBY
  end

  def test_no_folding_for_single_line_method_definitions
    assert_no_folding(<<~RUBY)
      def foo; end
      def bar; end
      def baz; end
    RUBY
  end

  def test_folding_classes
    ranges = [
      { startLine: 0, endLine: 4, kind: "region" },
      { startLine: 1, endLine: 3, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      class Foo
        def bar
          puts "Hello!"
        end
      end
    RUBY
  end

  def test_folding_singleton_classes
    ranges = [
      { startLine: 0, endLine: 3, kind: "region" },
      { startLine: 1, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      class Foo
        class << self
        end
      end
    RUBY
  end

  def test_folding_modules
    ranges = [
      { startLine: 0, endLine: 6, kind: "region" },
      { startLine: 1, endLine: 2, kind: "region" },
      { startLine: 4, endLine: 5, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      module Foo
        class Bar
        end

        module Baz
        end
      end
    RUBY
  end

  def test_folding_do_blocks
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      list.each do |item|
        puts item
      end
    RUBY
  end

  def test_folding_multiline_block
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      list.each { |item|
        puts item
      }
    RUBY
  end

  def test_folding_lambdas
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      lambda { |item|
        puts item
      }
    RUBY
  end

  def test_no_folding_for_single_line_lambdas
    assert_no_folding(<<~RUBY)
      lambda { |item| puts item }
    RUBY
  end

  def test_no_folding_for_single_line_arrays
    assert_no_folding(<<~RUBY)
      a = [1, 2]
    RUBY
  end

  def test_folding_multiline_arrays
    ranges = [
      { startLine: 0, endLine: 3, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      a = [
        1,
        2,
      ]
    RUBY
  end

  def test_no_folding_for_single_line_hashes
    assert_no_folding(<<~RUBY)
      a = { b: 1, c: 2 }
    RUBY
  end

  def test_folding_multiline_hashes
    ranges = [
      { startLine: 0, endLine: 3, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      a = {
        b: 1,
        c: 2,
      }
    RUBY
  end

  def test_folding_multiline_if_statements
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      if true
        puts "Hello!"
      end
    RUBY
  end

  def test_no_folding_if_guard
    assert_no_folding(<<~RUBY)
      puts "Hello!" if true
    RUBY
  end

  def test_folding_multiline_unless_statements
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      unless true
        puts "Yes!"
      end
    RUBY
  end

  def test_folding_while
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      while true
        puts "loop!"
      end
    RUBY
  end

  def test_no_folding_for_single_line_while
    assert_no_folding(<<~RUBY)
      puts "loop!" while true
    RUBY
  end

  def test_folding_until
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      until false
        puts "loop!"
      end
    RUBY
  end

  def test_no_folding_for_single_line_until
    assert_no_folding(<<~RUBY)
      puts "loop!" until false
    RUBY
  end

  def test_folding_for_loop
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      for i in 0..10
        puts "loop!"
      end
    RUBY
  end

  def test_folding_multiline_function_invocation
    ranges = [
      { startLine: 0, endLine: 3, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      invocation(
        a: 1,
        b: 2,
      )
    RUBY
  end

  def test_folding_multiline_method_invocation
    ranges = [
      { startLine: 0, endLine: 3, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      foo.invocation(
        a: 1,
        b: 2,
      )
    RUBY
  end

  def test_folding_nested_multiline_method_invocation
    ranges = [
      { startLine: 0, endLine: 5, kind: "region" },
      { startLine: 1, endLine: 4, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      foo.invocation(
        another_invocation(
          1,
          2
        )
      )
    RUBY
  end

  def test_folding_nested_multiline_invocation_no_parenthesis
    ranges = [
      { startLine: 0, endLine: 3, kind: "region" },
      { startLine: 1, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      foo.invocation(
        another_invocation 1,
          2
      )
    RUBY
  end

  def test_folding_heredoc
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      <<-HEREDOC
        some text
      HEREDOC
    RUBY

    assert_ranges(<<~RUBY, ranges)
      <<~HEREDOC
        some text
      HEREDOC
    RUBY
  end

  def test_folding_multiline_if_else_statements
    ranges = [
      { startLine: 0, endLine: 6, kind: "region" },
      { startLine: 2, endLine: 3, kind: "region" },
      { startLine: 4, endLine: 5, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      if true
        puts "Yes!"
      elsif false
        puts "Maybe?"
      else
        puts "No"
      end
    RUBY
  end

  def test_folding_multiline_if_else_empty_statements
    ranges = [
      { startLine: 0, endLine: 3, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      if true
      elsif false
      else
      end
    RUBY
  end

  def test_folding_case_when
    ranges = [
      { startLine: 0, endLine: 5, kind: "region" },
      { startLine: 1, endLine: 2, kind: "region" },
      { startLine: 3, endLine: 4, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      case node
      when CaseNode
        puts "case"
      else
        puts "else"
      end
    RUBY
  end

  def test_folding_begin_rescue_ensure
    ranges = [
      { startLine: 0, endLine: 1, kind: "region" },
      { startLine: 2, endLine: 3, kind: "region" },
      { startLine: 4, endLine: 5, kind: "region" },
      { startLine: 6, endLine: 7, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      begin
        puts "begin"
      rescue StandardError => e
        puts "stderror"
      rescue Exception => e
        puts "exception"
      ensure
        puts "ensure"
      end
    RUBY
  end

  def test_folding_multiline_invocations_no_parenthesis
    ranges = [
      { startLine: 0, endLine: 3, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      has_many :something,
        class_name: "Something",
        foreign_key: :something_id,
        inverse_of: :something_else
    RUBY
  end

  def test_folding_comments
    ranges = [
      { startLine: 0, endLine: 2, kind: "comment" },
      { startLine: 4, endLine: 6, kind: "comment" },
      { startLine: 9, endLine: 10, kind: "comment" },
    ]
    assert_ranges(<<~RUBY, ranges)
      # First
      # Second
      # Third

      # Some method
      # docs
      # and examples
      def foo; end

      # Nothing after
      # This one
    RUBY
  end

  def test_folding_requires
    ranges = [
      { startLine: 0, endLine: 3, kind: "imports" },
    ]
    assert_ranges(<<~RUBY, ranges)
      require "foo"
      require_relative "bar"

      require "baz"
    RUBY
  end

  def test_folding_multiline_strings
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      "foo" \\
        "bar" \\
        "baz"
    RUBY
  end

  def test_folding_pattern_matching
    ranges = [
      { startLine: 0, endLine: 5, kind: "region" },
      { startLine: 1, endLine: 2, kind: "region" },
      { startLine: 3, endLine: 4, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      case foo
      in { a: 1 }
        puts "a"
      else
        puts "nothing"
      end
    RUBY
  end

  def test_folding_chained_invocations
    ranges = [
      { startLine: 1, endLine: 7, kind: "region" },
      { startLine: 2, endLine: 6, kind: "region" },
      { startLine: 4, endLine: 5, kind: "region" },
      { startLine: 0, endLine: 11, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      []
        .select do |x|
          if x.odd?
            x + 2
          else
            x + 1
          end
        end
        .map { |x| x }
        .drop(1)
        .select()
        .sort
    RUBY
  end

  private

  def assert_no_folding(source)
    parsed_tree = RubyLsp::Store::ParsedTree.new(source)
    actual = RubyLsp::Requests::FoldingRanges.run(parsed_tree)
    assert_empty(JSON.parse(actual.to_json, symbolize_names: true))
  end

  def assert_ranges(source, expected_ranges)
    parsed_tree = RubyLsp::Store::ParsedTree.new(source)
    actual = RubyLsp::Requests::FoldingRanges.run(parsed_tree)
    assert_equal(expected_ranges, JSON.parse(actual.to_json, symbolize_names: true))
  end
end
