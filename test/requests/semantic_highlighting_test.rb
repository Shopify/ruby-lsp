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

  def test_aref_field
    tokens = [
      { delta_line: 1, delta_start_char: 2, length: 1, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 2, length: 1, token_type: 0, token_modifiers: 0 },
    ]

    assert_tokens(tokens, <<~RUBY)
      def my_method
        a = []
        a[1] = "foo"
      end
    RUBY
  end

  def test_var_aref_variable
    tokens = [
      { delta_line: 1, delta_start_char: 2, length: 1, token_type: 0, token_modifiers: 0 },
    ]

    assert_tokens(tokens, <<~RUBY)
      def my_method
        a = :hello # local variable arefs should match
        @my_ivar = true # ivar arefs should not match
        $global_var = 1  # global arefs should not match
        @@class_var = "hello" # cvar refs should not match
      end
      Foo = 3.14 # constant refs should not match
    RUBY
  end

  def test_var_field_variable
    tokens = [
      { delta_line: 1, delta_start_char: 2, length: 1, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 2, length: 1, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 2, length: 1, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 2, length: 1, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 2, length: 1, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 2, length: 1, token_type: 0, token_modifiers: 0 },
      { delta_line: 0, delta_start_char: 4, length: 1, token_type: 0, token_modifiers: 0 },
    ]

    assert_tokens(tokens, <<~RUBY)
      def my_method
        b = Foo # constant refs should not match
        a = true # keyword refs should not match
        a = @my_ivar # ivar refs should not match
        a = $global_var # global refs should not match
        a = @@class_var # cvar refs should not match
        a = b # local variable refs should match
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

  def test_command_invocation_variable
    tokens = [
      { delta_line: 0, delta_start_char: 0, length: 3, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 0, length: 4, token_type: 1, token_modifiers: 0 },
      { delta_line: 0, delta_start_char: 5, length: 3, token_type: 0, token_modifiers: 0 },
    ]

    assert_tokens(tokens, <<~RUBY)
      var = "Hello"
      puts var
    RUBY
  end

  def test_command_call
    tokens = [
      { delta_line: 0, delta_start_char: 0, length: 3, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 0, length: 6, token_type: 1, token_modifiers: 0 },
      { delta_line: 0, delta_start_char: 7, length: 10, token_type: 1, token_modifiers: 0 },
      { delta_line: 0, delta_start_char: 11, length: 3, token_type: 0, token_modifiers: 0 },
    ]

    assert_tokens(tokens, <<~RUBY)
      var = "Hello"
      object.invocation var
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

  def test_call_invocation_with_variable_receiver
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

  def test_call_invocation_with_variable_receiver_and_arguments
    tokens = [
      { delta_line: 1, delta_start_char: 2, length: 3, token_type: 0, token_modifiers: 0 },
      { delta_line: 0, delta_start_char: 5, length: 3, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 2, length: 3, token_type: 0, token_modifiers: 0 },
      { delta_line: 0, delta_start_char: 4, length: 6, token_type: 1, token_modifiers: 0 },
      { delta_line: 0, delta_start_char: 7, length: 3, token_type: 0, token_modifiers: 0 },
    ]

    assert_tokens(tokens, <<~RUBY)
      def some_method
        var, arg = "Hello"
        var.upcase(arg)
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

  def test_fcall_invocation_variable_arguments
    tokens = [
      { delta_line: 1, delta_start_char: 2, length: 3, token_type: 0, token_modifiers: 0 },
      { delta_line: 1, delta_start_char: 2, length: 10, token_type: 1, token_modifiers: 0 },
      { delta_line: 0, delta_start_char: 11, length: 3, token_type: 0, token_modifiers: 0 },
    ]

    assert_tokens(tokens, <<~RUBY)
      def some_method
        var = 1
        invocation(var)
      end
    RUBY
  end

  private

  def assert_tokens(expected, source_code)
    document = RubyLsp::Document.new(source_code)
    assert_equal(
      inline_tokens(expected),
      RubyLsp::Requests::SemanticHighlighting.run(document).data
    )
  end

  def inline_tokens(tokens)
    tokens.flat_map do |token|
      [token[:delta_line], token[:delta_start_char], token[:length], token[:token_type], token[:token_modifiers]]
    end
  end
end
