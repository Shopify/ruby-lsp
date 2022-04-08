# frozen_string_literal: true

require "test_helper"

class FoldingRangesTest < Minitest::Test
  # Folding

  def test_folding_array_literal
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

  def test_folding_brace_block
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      list.each { |item|
        puts item
      }
    RUBY
  end

  def test_folding_call_and_arguments
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

  def test_folding_call_and_nested_fcall
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

  def test_folding_call_and_nested_command
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

  def test_folding_call_chained
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

  def test_folding_case_in_else
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

  def test_folding_class_declaration
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

  def test_folding_command
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

  def test_folding_command_call
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      self.foo a,
        b,
        c
    RUBY
  end

  def test_folding_command_call_chained
    ranges = [
      { startLine: 0, endLine: 3, kind: "region" },
      { startLine: 1, endLine: 3, kind: "region" },
      { startLine: 2, endLine: 3, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      self
        .foo a
        .bar b
        .baz z
    RUBY
  end

  def test_folding_command_for_require
    ranges = [
      { startLine: 0, endLine: 3, kind: "imports" },
    ]
    assert_ranges(<<~RUBY, ranges)
      require "foo"
      require_relative "bar"

      require "baz"
    RUBY
  end

  def test_folding_comment
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

  def test_folding_def
    ranges = [{ startLine: 0, endLine: 3, kind: "region" }]
    assert_ranges(<<~RUBY, ranges)
      def foo
        a = 2
        puts "a"
      end
    RUBY
  end

  def test_folding_def_with_multline_params
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

  def test_folding_defs
    ranges = [{ startLine: 0, endLine: 3, kind: "region" }]
    assert_ranges(<<~RUBY, ranges)
      def self.foo
        a = 2
        puts "a"
      end
    RUBY
  end

  def test_folding_defs_with_multiline_params
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

  def test_folding_do_block
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      list.each do |item|
        puts item
      end
    RUBY
  end

  def test_folding_fcall_with_arguments
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

  def test_folding_for
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      for i in 0..10
        puts "loop!"
      end
    RUBY
  end

  def test_folding_hash_literal
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

  def test_folding_if
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      if true
        puts "Hello!"
      end
    RUBY
  end

  def test_folding_if_elsif_else
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

  def test_folding_if_elsif_else_with_empty_statements
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

  def test_folding_module_declaration
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

  def test_folding_sclass
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

  def test_folding_string_concat
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      "foo" \\
        "bar" \\
        "baz"
    RUBY
  end

  def test_folding_unless
    ranges = [
      { startLine: 0, endLine: 2, kind: "region" },
    ]
    assert_ranges(<<~RUBY, ranges)
      unless true
        puts "Yes!"
      end
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

  # No folding

  def test_no_folding_array_literal_oneline
    assert_no_folding(<<~RUBY)
      a = [1, 2]
    RUBY
  end

  def test_no_folding_brace_block_oneline
    assert_no_folding(<<~RUBY)
      lambda { |item| puts item }
    RUBY
  end

  def test_no_folding_def_and_defs_oneline
    assert_no_folding(<<~RUBY)
      def foo; end
      def bar; end
      def self.baz; end
    RUBY
  end

  def test_no_folding_hash_literal_oneline
    assert_no_folding(<<~RUBY)
      a = { b: 1, c: 2 }
    RUBY
  end

  def test_no_folding_if_mod
    assert_no_folding(<<~RUBY)
      puts "Hello!" if true
    RUBY
  end

  def test_no_folding_until_mod
    assert_no_folding(<<~RUBY)
      puts "loop!" until false
    RUBY
  end

  def test_no_folding_while_mod
    assert_no_folding(<<~RUBY)
      puts "loop!" while true
    RUBY
  end

  private

  def assert_no_folding(source)
    store = RubyLsp::Store.new
    store.set("foo.rb", source)
    actual = RubyLsp::Requests::FoldingRanges.run("foo.rb", store)
    assert_empty(JSON.parse(actual.to_json, symbolize_names: true))
  end

  def assert_ranges(source, expected_ranges)
    store = RubyLsp::Store.new
    store.set("foo.rb", source)
    actual = RubyLsp::Requests::FoldingRanges.run("foo.rb", store)
    assert_equal(expected_ranges, JSON.parse(actual.to_json, symbolize_names: true))
  end
end
