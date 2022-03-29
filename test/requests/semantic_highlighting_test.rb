# frozen_string_literal: true

require "test_helper"

class SemanticHighlightingTest < Minitest::Test
  def test_local_variables
    tokens = [
      1, 2, 3, 0, 0,
      1, 2, 3, 0, 0,
    ]

    assert_tokens(tokens, <<~RUBY)
      def my_method
        var = 1
        var
      end
    RUBY
  end

  def test_multi_assignment
    tokens = [
      1, 2, 1, 0, 0,
      0, 3, 1, 0, 0,
      1, 2, 1, 0, 0,
      1, 2, 1, 0, 0,
    ]

    assert_tokens(tokens, <<~RUBY)
      def my_method
        a, b = [1, 2]
        a
        b
      end
    RUBY
  end

  def test_command_invocation
    tokens = [
      0, 0, 4, 1, 0,
    ]

    assert_tokens(tokens, <<~RUBY)
      puts "Hello"
    RUBY
  end

  def test_call_invocation
    tokens = [
      0, 8, 6, 1, 0,
    ]

    assert_tokens(tokens, <<~RUBY)
      "Hello".upcase
    RUBY
  end

  def test_vcall_invocation
    tokens = [
      1, 2, 10, 1, 0,
    ]

    assert_tokens(tokens, <<~RUBY)
      def some_method
        invocation
      end
    RUBY
  end

  def test_fcall_invocation
    tokens = [
      1, 2, 10, 1, 0,
    ]

    assert_tokens(tokens, <<~RUBY)
      def some_method
        invocation(1, 2, 3)
      end
    RUBY
  end

  private

  def assert_tokens(expected, source_code)
    parsed_tree = RubyLsp::Store::ParsedTree.new(source_code)
    assert_equal(
      expected,
      RubyLsp::Requests::SemanticHighlighting.run(parsed_tree).data
    )
  end
end
