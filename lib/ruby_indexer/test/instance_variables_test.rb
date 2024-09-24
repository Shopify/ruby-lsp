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
      owner = T.must(entry.owner)
      assert_instance_of(Entry::Class, owner)
      assert_equal("Foo::Bar", owner.name)
    end

    def test_instance_variable_with_multibyte_characters
      index(<<~RUBY)
        class Foo
          def initialize
            @あ = 1
          end
        end
      RUBY

      assert_entry("@あ", Entry::InstanceVariable, "/fake/path/foo.rb:2-4:2-6")
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
      owner = T.must(entry.owner)
      assert_instance_of(Entry::Class, owner)
      assert_equal("Foo::Bar", owner.name)
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
      owner = T.must(entry.owner)
      assert_instance_of(Entry::Class, owner)
      assert_equal("Foo::Bar", owner.name)
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
      owner = T.must(entry.owner)
      assert_instance_of(Entry::Class, owner)
      assert_equal("Foo::Bar", owner.name)
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
      owner = T.must(entry.owner)
      assert_instance_of(Entry::Class, owner)
      assert_equal("Foo::Bar", owner.name)

      entry = T.must(@index["@b"]&.first)
      owner = T.must(entry.owner)
      assert_instance_of(Entry::Class, owner)
      assert_equal("Foo::Bar", owner.name)
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

            class << self
              def hello
                @b = 123
              end

              @c = 123
            end
          end
        end
      RUBY

      assert_entry("@a", Entry::InstanceVariable, "/fake/path/foo.rb:2-4:2-6")

      entry = T.must(@index["@a"]&.first)
      owner = T.must(entry.owner)
      assert_instance_of(Entry::SingletonClass, owner)
      assert_equal("Foo::Bar::<Class:Bar>", owner.name)

      assert_entry("@b", Entry::InstanceVariable, "/fake/path/foo.rb:6-8:6-10")

      entry = T.must(@index["@b"]&.first)
      owner = T.must(entry.owner)
      assert_instance_of(Entry::SingletonClass, owner)
      assert_equal("Foo::Bar::<Class:Bar>", owner.name)

      assert_entry("@c", Entry::InstanceVariable, "/fake/path/foo.rb:9-6:9-8")

      entry = T.must(@index["@c"]&.first)
      owner = T.must(entry.owner)
      assert_instance_of(Entry::SingletonClass, owner)
      assert_equal("Foo::Bar::<Class:Bar>::<Class:<Class:Bar>>", owner.name)
    end

    def test_top_level_instance_variables
      index(<<~RUBY)
        @a = 123
      RUBY

      entry = T.must(@index["@a"]&.first)
      assert_nil(entry.owner)
    end

    def test_class_instance_variables_inside_self_method
      index(<<~RUBY)
        class Foo
          def self.bar
            @a = 123
          end
        end
      RUBY

      entry = T.must(@index["@a"]&.first)
      owner = T.must(entry.owner)
      assert_instance_of(Entry::SingletonClass, owner)
      assert_equal("Foo::<Class:Foo>", owner.name)
    end

    def test_instance_variable_inside_dynamic_method_declaration
      index(<<~RUBY)
        class Foo
          def something.bar
            @a = 123
          end
        end
      RUBY

      # If the surrounding method is beind defined on any dynamic value that isn't `self`, then we attribute the
      # instance variable to the wrong owner since there's no way to understand that statically
      entry = T.must(@index["@a"]&.first)
      owner = T.must(entry.owner)
      assert_instance_of(Entry::Class, owner)
      assert_equal("Foo", owner.name)
    end
  end
end
