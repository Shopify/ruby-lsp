# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyIndexer
  class ReferenceFinderTest < Minitest::Test
    def test_finds_constant_references
      refs = find_const_references("Foo::Bar", <<~RUBY)
        module Foo
          class Bar
          end

          Bar
        end

        Foo::Bar
      RUBY

      assert_equal("Bar", refs[0].name)
      assert_equal(2, refs[0].location.start_line)

      assert_equal("Bar", refs[1].name)
      assert_equal(5, refs[1].location.start_line)

      assert_equal("Foo::Bar", refs[2].name)
      assert_equal(8, refs[2].location.start_line)
    end

    def test_finds_constant_references_inside_singleton_contexts
      refs = find_const_references("Foo::<Class:Foo>::Bar", <<~RUBY)
        class Foo
          class << self
            class Bar
            end

            Bar
          end
        end
      RUBY

      assert_equal("Bar", refs[0].name)
      assert_equal(3, refs[0].location.start_line)

      assert_equal("Bar", refs[1].name)
      assert_equal(6, refs[1].location.start_line)
    end

    def test_finds_top_level_constant_references
      refs = find_const_references("Bar", <<~RUBY)
        class Bar
        end

        class Foo
          ::Bar

          class << self
            ::Bar
          end
        end
      RUBY

      assert_equal("Bar", refs[0].name)
      assert_equal(1, refs[0].location.start_line)

      assert_equal("::Bar", refs[1].name)
      assert_equal(5, refs[1].location.start_line)

      assert_equal("::Bar", refs[2].name)
      assert_equal(8, refs[2].location.start_line)
    end

    def test_finds_method_references
      refs = find_method_references("foo", <<~RUBY)
        class Bar
          def foo
          end

          def baz
            foo
          end
        end
      RUBY

      assert_equal(2, refs.size)

      assert_equal("foo", refs[0].name)
      assert_equal(2, refs[0].location.start_line)

      assert_equal("foo", refs[1].name)
      assert_equal(6, refs[1].location.start_line)
    end

    def test_does_not_mismatch_on_readers_and_writers
      refs = find_method_references("foo", <<~RUBY)
        class Bar
          def foo
          end

          def foo=(value)
          end

          def baz
            self.foo = 1
            self.foo
          end
        end
      RUBY

      # We want to match `foo` but not `foo=`
      assert_equal(2, refs.size)

      assert_equal("foo", refs[0].name)
      assert_equal(2, refs[0].location.start_line)

      assert_equal("foo", refs[1].name)
      assert_equal(10, refs[1].location.start_line)
    end

    def test_matches_writers
      refs = find_method_references("foo=", <<~RUBY)
        class Bar
          def foo
          end

          def foo=(value)
          end

          def baz
            self.foo = 1
            self.foo
          end
        end
      RUBY

      # We want to match `foo=` but not `foo`
      assert_equal(2, refs.size)

      assert_equal("foo=", refs[0].name)
      assert_equal(5, refs[0].location.start_line)

      assert_equal("foo=", refs[1].name)
      assert_equal(9, refs[1].location.start_line)
    end

    def test_find_inherited_methods
      refs = find_method_references("foo", <<~RUBY)
        class Bar
          def foo
          end
        end

        class Baz < Bar
          super.foo
        end
      RUBY

      assert_equal(2, refs.size)

      assert_equal("foo", refs[0].name)
      assert_equal(2, refs[0].location.start_line)

      assert_equal("foo", refs[1].name)
      assert_equal(7, refs[1].location.start_line)
    end

    def test_finds_methods_created_in_mixins
      refs = find_method_references("foo", <<~RUBY)
        module Mixin
          def foo
          end
        end

        class Bar
          include Mixin
        end

        Bar.foo
      RUBY

      assert_equal(2, refs.size)

      assert_equal("foo", refs[0].name)
      assert_equal(2, refs[0].location.start_line)

      assert_equal("foo", refs[1].name)
      assert_equal(10, refs[1].location.start_line)
    end

    def test_finds_singleton_methods
      # The current implementation matches on both `Bar.foo` and `Bar#foo` even though they are different

      refs = find_method_references("foo", <<~RUBY)
        class Bar
          class << self
            def foo
            end
          end

          def foo
          end
        end

        Bar.foo
      RUBY

      assert_equal(3, refs.size)

      assert_equal("foo", refs[0].name)
      assert_equal(3, refs[0].location.start_line)

      assert_equal("foo", refs[1].name)
      assert_equal(7, refs[1].location.start_line)

      assert_equal("foo", refs[2].name)
      assert_equal(11, refs[2].location.start_line)
    end

    def test_finds_instance_variable_references
      refs = find_instance_variable_references("@name", ["Foo"], <<~RUBY)
        class Foo
          def initialize
            @name = "foo"
          end
          def name
            @name
          end
          def name_capital
            @name[0]
          end
        end

        class Bar
          def initialize
            @name = "foo"
          end
          def name
            @name
          end
        end
      RUBY
      assert_equal(3, refs.size)

      assert_equal("@name", refs[0].name)
      assert_equal(3, refs[0].location.start_line)

      assert_equal("@name", refs[1].name)
      assert_equal(6, refs[1].location.start_line)

      assert_equal("@name", refs[2].name)
      assert_equal(9, refs[2].location.start_line)
    end

    def test_finds_instance_variable_write_references
      refs = find_instance_variable_references("@foo", ["Foo"], <<~RUBY)
        class Foo
          def write
            @foo = 1
            @foo &&= 2
            @foo ||= 3
            @foo += 4
            @foo, @bar = []
          end
        end
      RUBY
      assert_equal(5, refs.size)

      assert_equal(["@foo"], refs.map(&:name).uniq)
      assert_equal(3, refs[0].location.start_line)
      assert_equal(4, refs[1].location.start_line)
      assert_equal(5, refs[2].location.start_line)
      assert_equal(6, refs[3].location.start_line)
      assert_equal(7, refs[4].location.start_line)
    end

    def test_finds_instance_variable_references_in_owner_ancestors
      refs = find_instance_variable_references("@name", ["Foo", "Base", "Top", "Parent"], <<~RUBY)
        module Base
          def change_name(name)
            @name = name
          end
          def name
            @name
          end

          module ::Top
            def name
              @name
            end
          end
        end

        class Parent
          def initialize
            @name = "parent"
          end
          def name_capital
            @name[0]
          end
        end

        class Foo < Parent
          include Base
          def initialize
            @name = "foo"
          end
          def name
            @name
          end
        end

        class Bar
          def name
            @name = "bar"
          end
        end
      RUBY
      assert_equal(7, refs.size)

      assert_equal("@name", refs[0].name)
      assert_equal(3, refs[0].location.start_line)

      assert_equal("@name", refs[1].name)
      assert_equal(6, refs[1].location.start_line)

      assert_equal("@name", refs[2].name)
      assert_equal(11, refs[2].location.start_line)

      assert_equal("@name", refs[3].name)
      assert_equal(18, refs[3].location.start_line)

      assert_equal("@name", refs[4].name)
      assert_equal(21, refs[4].location.start_line)

      assert_equal("@name", refs[5].name)
      assert_equal(28, refs[5].location.start_line)

      assert_equal("@name", refs[6].name)
      assert_equal(31, refs[6].location.start_line)
    end

    def test_accounts_for_reopened_classes
      refs = find_const_references("Foo", <<~RUBY)
        class Foo
        end
        class Foo
          class Bar
          end
        end

        Foo.new
      RUBY

      assert_equal(3, refs.size)

      assert_equal("Foo", refs[0].name)
      assert_equal(1, refs[0].location.start_line)

      assert_equal("Foo", refs[1].name)
      assert_equal(3, refs[1].location.start_line)

      assert_equal("Foo", refs[2].name)
      assert_equal(8, refs[2].location.start_line)
    end

    private

    def find_const_references(const_name, source)
      target = ReferenceFinder::ConstTarget.new(const_name)
      find_references(target, source)
    end

    def find_method_references(method_name, source)
      target = ReferenceFinder::MethodTarget.new(method_name)
      find_references(target, source)
    end

    def find_instance_variable_references(instance_variable_name, owner_ancestors, source)
      target = ReferenceFinder::InstanceVariableTarget.new(instance_variable_name, owner_ancestors)
      find_references(target, source)
    end

    def find_references(target, source)
      file_path = "/fake.rb"
      uri = URI::Generic.from_path(path: file_path)
      index = Index.new
      index.index_single(uri, source)
      parse_result = Prism.parse(source)
      dispatcher = Prism::Dispatcher.new
      finder = ReferenceFinder.new(target, index, dispatcher, uri)
      dispatcher.visit(parse_result.value)
      finder.references
    end
  end
end
