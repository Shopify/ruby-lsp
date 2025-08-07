# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class ClassVariableTest < TestCase
    def test_class_variable_and_write
      index(<<~RUBY)
        class Foo
          @@bar &&= 1
        end
      RUBY

      assert_entry("@@bar", Entry::ClassVariable, "/fake/path/foo.rb:1-2:1-7")

      entry = @index["@@bar"]&.first #: as Entry::ClassVariable
      owner = entry.owner #: as !nil
      assert_instance_of(Entry::Class, owner)
      assert_equal("Foo", owner.name)
    end

    def test_class_variable_operator_write
      index(<<~RUBY)
        class Foo
          @@bar += 1
        end
      RUBY

      assert_entry("@@bar", Entry::ClassVariable, "/fake/path/foo.rb:1-2:1-7")
    end

    def test_class_variable_or_write
      index(<<~RUBY)
        class Foo
          @@bar ||= 1
        end
      RUBY

      assert_entry("@@bar", Entry::ClassVariable, "/fake/path/foo.rb:1-2:1-7")
    end

    def test_class_variable_target_node
      index(<<~RUBY)
        class Foo
          @@foo, @@bar = 1
        end
      RUBY

      assert_entry("@@foo", Entry::ClassVariable, "/fake/path/foo.rb:1-2:1-7")
      assert_entry("@@bar", Entry::ClassVariable, "/fake/path/foo.rb:1-9:1-14")

      entry = @index["@@foo"]&.first #: as Entry::ClassVariable
      owner = entry.owner #: as !nil
      assert_instance_of(Entry::Class, owner)
      assert_equal("Foo", owner.name)

      entry = @index["@@bar"]&.first #: as Entry::ClassVariable
      owner = entry.owner #: as !nil
      assert_instance_of(Entry::Class, owner)
      assert_equal("Foo", owner.name)
    end

    def test_class_variable_write
      index(<<~RUBY)
        class Foo
          @@bar = 1
        end
      RUBY

      assert_entry("@@bar", Entry::ClassVariable, "/fake/path/foo.rb:1-2:1-7")
    end

    def test_empty_name_class_variable
      index(<<~RUBY)
        module Foo
          @@ = 1
        end
      RUBY

      refute_entry("@@")
    end

    def test_top_level_class_variable
      index(<<~RUBY)
        @@foo = 123
      RUBY

      entry = @index["@@foo"]&.first #: as Entry::ClassVariable
      assert_nil(entry.owner)
    end

    def test_class_variable_inside_self_method
      index(<<~RUBY)
        class Foo
          def self.bar
            @@bar = 123
          end
        end
      RUBY

      entry = @index["@@bar"]&.first #: as Entry::ClassVariable
      owner = entry.owner #: as !nil
      assert_instance_of(Entry::Class, owner)
      assert_equal("Foo", owner.name)
    end

    def test_class_variable_inside_singleton_class
      index(<<~RUBY)
        class Foo
          class << self
            @@bar = 123
          end
        end
      RUBY

      entry = @index["@@bar"]&.first #: as Entry::ClassVariable
      owner = entry.owner #: as !nil
      assert_instance_of(Entry::Class, owner)
      assert_equal("Foo", owner.name)
    end

    def test_class_variable_in_singleton_class_method
      index(<<~RUBY)
        class Foo
          class << self
            def self.bar
              @@bar = 123
            end
          end
        end
      RUBY

      entry = @index["@@bar"]&.first #: as Entry::ClassVariable
      owner = entry.owner #: as !nil
      assert_instance_of(Entry::Class, owner)
      assert_equal("Foo", owner.name)
    end
  end
end
