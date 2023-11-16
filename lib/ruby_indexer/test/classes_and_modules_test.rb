# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class ClassesAndModulesTest < TestCase
    def test_empty_statements_class
      index(<<~RUBY)
        class Foo
        end
      RUBY

      assert_entry("Foo", Entry::Class, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_class_with_statements
      index(<<~RUBY)
        class Foo
          def something; end
        end
      RUBY

      assert_entry("Foo", Entry::Class, "/fake/path/foo.rb:0-0:2-3")
    end

    def test_colon_colon_class
      index(<<~RUBY)
        class ::Foo
        end
      RUBY

      assert_entry("Foo", Entry::Class, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_colon_colon_class_inside_class
      index(<<~RUBY)
        class Bar
          class ::Foo
          end
        end
      RUBY

      assert_entry("Bar", Entry::Class, "/fake/path/foo.rb:0-0:3-3")
      assert_entry("Foo", Entry::Class, "/fake/path/foo.rb:1-2:2-5")
    end

    def test_namespaced_class
      index(<<~RUBY)
        class Foo::Bar
        end
      RUBY

      assert_entry("Foo::Bar", Entry::Class, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_dynamically_namespaced_class
      index(<<~RUBY)
        class self::Bar
        end
      RUBY

      refute_entry("self::Bar")
    end

    def test_empty_statements_module
      index(<<~RUBY)
        module Foo
        end
      RUBY

      assert_entry("Foo", Entry::Module, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_module_with_statements
      index(<<~RUBY)
        module Foo
          def something; end
        end
      RUBY

      assert_entry("Foo", Entry::Module, "/fake/path/foo.rb:0-0:2-3")
    end

    def test_colon_colon_module
      index(<<~RUBY)
        module ::Foo
        end
      RUBY

      assert_entry("Foo", Entry::Module, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_namespaced_module
      index(<<~RUBY)
        module Foo::Bar
        end
      RUBY

      assert_entry("Foo::Bar", Entry::Module, "/fake/path/foo.rb:0-0:1-3")
    end

    def test_dynamically_namespaced_module
      index(<<~RUBY)
        module self::Bar
        end
      RUBY

      refute_entry("self::Bar")
    end

    def test_nested_modules_and_classes
      index(<<~RUBY)
        module Foo
          class Bar
          end

          module Baz
            class Qux
              class Something
              end
            end
          end
        end
      RUBY

      assert_entry("Foo", Entry::Module, "/fake/path/foo.rb:0-0:10-3")
      assert_entry("Foo::Bar", Entry::Class, "/fake/path/foo.rb:1-2:2-5")
      assert_entry("Foo::Baz", Entry::Module, "/fake/path/foo.rb:4-2:9-5")
      assert_entry("Foo::Baz::Qux", Entry::Class, "/fake/path/foo.rb:5-4:8-7")
      assert_entry("Foo::Baz::Qux::Something", Entry::Class, "/fake/path/foo.rb:6-6:7-9")
    end

    def test_deleting_from_index_based_on_file_path
      index(<<~RUBY)
        class Foo
        end
      RUBY

      assert_entry("Foo", Entry::Class, "/fake/path/foo.rb:0-0:1-3")

      @index.delete(IndexablePath.new(nil, "/fake/path/foo.rb"))
      refute_entry("Foo")
      assert_empty(@index.instance_variable_get(:@files_to_entries))
    end

    def test_comments_can_be_attached_to_a_class
      index(<<~RUBY)
        # This is method comment
        def foo; end
        # This is a Foo comment
        # This is another Foo comment
        class Foo
          # This should not be attached
        end

        # Ignore me

        # This Bar comment has 1 line padding

        class Bar; end
      RUBY

      foo_entry = @index["Foo"].first
      assert_equal("This is a Foo comment\nThis is another Foo comment", foo_entry.comments.join("\n"))

      bar_entry = @index["Bar"].first
      assert_equal("This Bar comment has 1 line padding", bar_entry.comments.join("\n"))
    end

    def test_comments_can_be_attached_to_a_namespaced_class
      index(<<~RUBY)
        # This is a Foo comment
        # This is another Foo comment
        class Foo
          # This is a Bar comment
          class Bar; end
        end
      RUBY

      foo_entry = @index["Foo"].first
      assert_equal("This is a Foo comment\nThis is another Foo comment", foo_entry.comments.join("\n"))

      bar_entry = @index["Foo::Bar"].first
      assert_equal("This is a Bar comment", bar_entry.comments.join("\n"))
    end

    def test_comments_can_be_attached_to_a_reopened_class
      index(<<~RUBY)
        # This is a Foo comment
        class Foo; end

        # This is another Foo comment
        class Foo; end
      RUBY

      first_foo_entry = @index["Foo"][0]
      assert_equal("This is a Foo comment", first_foo_entry.comments.join("\n"))

      second_foo_entry = @index["Foo"][1]
      assert_equal("This is another Foo comment", second_foo_entry.comments.join("\n"))
    end

    def test_comments_removes_the_leading_pound_and_space
      index(<<~RUBY)
        # This is a Foo comment
        class Foo; end

        #This is a Bar comment
        class Bar; end
      RUBY

      first_foo_entry = @index["Foo"][0]
      assert_equal("This is a Foo comment", first_foo_entry.comments.join("\n"))

      second_foo_entry = @index["Bar"][0]
      assert_equal("This is a Bar comment", second_foo_entry.comments.join("\n"))
    end

    def test_private_class_and_module_indexing
      index(<<~RUBY)
        class A
          class B; end
          private_constant(:B)

          module C; end
          private_constant("C")

          class D; end
        end
      RUBY

      b_const = @index["A::B"].first
      assert_equal(:private, b_const.visibility)

      c_const = @index["A::C"].first
      assert_equal(:private, c_const.visibility)

      d_const = @index["A::D"].first
      assert_equal(:public, d_const.visibility)
    end

    def test_keeping_track_of_super_classes
      index(<<~RUBY)
        class Foo < Bar
        end

        class Baz
        end

        module Something
          class Baz
          end

          class Qux < ::Baz
          end
        end

        class FinalThing < Something::Baz
        end
      RUBY

      foo = T.must(@index["Foo"].first)
      assert_equal("Bar", foo.parent_class)

      baz = T.must(@index["Baz"].first)
      assert_nil(baz.parent_class)

      qux = T.must(@index["Something::Qux"].first)
      assert_equal("::Baz", qux.parent_class)

      final_thing = T.must(@index["FinalThing"].first)
      assert_equal("Something::Baz", final_thing.parent_class)
    end
  end
end
