# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class InstanceVariableTest < TestCase
    def test_instance_variable_write
      index(<<~RUBY)
        module Foo
          class Bar
            def initialize
              # Hello
              @a = 1
            end
          end
        end
      RUBY

      assert_entry("@a", Entry::InstanceVariable, "/fake/path/foo.rb:4-6:4-8")

      entry = T.must(@index["@a"]&.first)
      assert_equal("Foo::Bar", T.must(entry.owner).name)
    end

    def test_instance_variable_and_write
      index(<<~RUBY)
        module Foo
          class Bar
            def initialize
              # Hello
              @a &&= value
            end
          end
        end
      RUBY

      assert_entry("@a", Entry::InstanceVariable, "/fake/path/foo.rb:4-6:4-8")

      entry = T.must(@index["@a"]&.first)
      assert_equal("Foo::Bar", T.must(entry.owner).name)
    end

    def test_instance_variable_operator_write
      index(<<~RUBY)
        module Foo
          class Bar
            def initialize
              # Hello
              @a += value
            end
          end
        end
      RUBY

      assert_entry("@a", Entry::InstanceVariable, "/fake/path/foo.rb:4-6:4-8")

      entry = T.must(@index["@a"]&.first)
      assert_equal("Foo::Bar", T.must(entry.owner).name)
    end

    def test_instance_variable_or_write
      index(<<~RUBY)
        module Foo
          class Bar
            def initialize
              # Hello
              @a ||= value
            end
          end
        end
      RUBY

      assert_entry("@a", Entry::InstanceVariable, "/fake/path/foo.rb:4-6:4-8")

      entry = T.must(@index["@a"]&.first)
      assert_equal("Foo::Bar", T.must(entry.owner).name)
    end

    def test_instance_variable_target
      index(<<~RUBY)
        module Foo
          class Bar
            def initialize
              # Hello
              @a, @b = [1, 2]
            end
          end
        end
      RUBY

      assert_entry("@a", Entry::InstanceVariable, "/fake/path/foo.rb:4-6:4-8")
      assert_entry("@b", Entry::InstanceVariable, "/fake/path/foo.rb:4-10:4-12")

      entry = T.must(@index["@a"]&.first)
      assert_equal("Foo::Bar", T.must(entry.owner).name)

      entry = T.must(@index["@b"]&.first)
      assert_equal("Foo::Bar", T.must(entry.owner).name)
    end

    def test_empty_name_instance_variables
      index(<<~RUBY)
        module Foo
          class Bar
            def initialize
              @ = 123
            end
          end
        end
      RUBY

      refute_entry("@")
    end

    def test_class_instance_variables
      index(<<~RUBY)
        module Foo
          class Bar
            @a = 123
          end
        end
      RUBY

      assert_entry("@a", Entry::InstanceVariable, "/fake/path/foo.rb:2-4:2-6")

      entry = T.must(@index["@a"]&.first)
      assert_equal("Foo::Bar", T.must(entry.owner).name)
    end
  end
end
