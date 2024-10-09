# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class GlobalVariableTest < TestCase
    def test_global_variable_and_write
      index(<<~RUBY)
        $foo &&= 1
      RUBY

      assert_entry("$foo", Entry::GlobalVariable, "/fake/path/foo.rb:0-0:0-4")
    end

    def test_global_variable_operator_write
      index(<<~RUBY)
        $foo += 1
      RUBY

      assert_entry("$foo", Entry::GlobalVariable, "/fake/path/foo.rb:0-0:0-4")
    end

    def test_global_variable_or_write
      index(<<~RUBY)
        $foo ||= 1
      RUBY

      assert_entry("$foo", Entry::GlobalVariable, "/fake/path/foo.rb:0-0:0-4")
    end

    def test_global_variable_target_node
      index(<<~RUBY)
        $foo, $bar = 1
      RUBY

      assert_entry("$foo", Entry::GlobalVariable, "/fake/path/foo.rb:0-0:0-4")
      assert_entry("$bar", Entry::GlobalVariable, "/fake/path/foo.rb:0-6:0-10")
    end

    def test_global_variable_write
      index(<<~RUBY)
        $foo = 1
      RUBY

      assert_entry("$foo", Entry::GlobalVariable, "/fake/path/foo.rb:0-0:0-4")
    end
  end
end
