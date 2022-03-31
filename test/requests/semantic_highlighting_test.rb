# frozen_string_literal: true

require "test_helper"

class SemanticHighlightingTest < Minitest::Test
  def test_local_variables
    tokens = [
      { delta_line: 1, delta_start_char: 2, length: 3, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 2, length: 3, token_type: 0, token_modifiers: 0 },
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
      { delta_line: 1, delta_start_char: 2, length: 1, token_type: 0, token_modifiers: 0 },
      { delta_line: 0, delta_start_char: 3, length: 1, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 2, length: 1, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 2, length: 1, token_type: 0, token_modifiers: 0 },
    ]

    assert_tokens(tokens, <<~RUBY)
      def my_method
        a, b = [1, 2]
        a
        b
      end
    RUBY
  end

  def test_aref_variable
    tokens = [
      { delta_line: 1, delta_start_char: 2, length: 1, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 2, length: 1, token_type: 0, token_modifiers: 0 },
    ]

    assert_tokens(tokens, <<~RUBY)
      def my_method
        a = []
        a[1]
      end
    RUBY
  end

  def test_command_invocation
    tokens = [
      { delta_line: 0, delta_start_char: 0, length: 4, token_type: 1, token_modifiers: 0 },
    ]

    assert_tokens(tokens, <<~RUBY)
      puts "Hello"
    RUBY
  end

  def test_call_invocation
    tokens = [
      { delta_line: 0, delta_start_char: 8, length: 6, token_type: 1, token_modifiers: 0 },
    ]

    assert_tokens(tokens, <<~RUBY)
      "Hello".upcase
    RUBY
  end

  def test_variable_receiver_in_call_invocation
    tokens = [
      { delta_line: 1, delta_start_char: 2, length: 3, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 2, length: 3, token_type: 0, token_modifiers: 0 },
      { delta_line: 0, delta_start_char: 4, length: 6, token_type: 1, token_modifiers: 0 },
    ]

    assert_tokens(tokens, <<~RUBY)
      def some_method
        var = "Hello"
        var.upcase
      end
    RUBY
  end

  def test_vcall_invocation
    tokens = [
      { delta_line: 1, delta_start_char: 2, length: 10, token_type: 1, token_modifiers: 0 },
    ]

    assert_tokens(tokens, <<~RUBY)
      def some_method
        invocation
      end
    RUBY
  end

  def test_fcall_invocation
    tokens = [
      { delta_line: 1, delta_start_char: 2, length: 10, token_type: 1, token_modifiers: 0 },
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
      inline_tokens(expected),
      RubyLsp::Requests::SemanticHighlighting.run(parsed_tree).data
    )
  end

  def inline_tokens(tokens)
    tokens.flat_map do |token|
      [token[:delta_line], token[:delta_start_char], token[:length], token[:token_type], token[:token_modifiers]]
    end
  end
end
