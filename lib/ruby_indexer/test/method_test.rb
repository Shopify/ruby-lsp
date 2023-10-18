# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class MethodTest < TestCase
    def test_method_with_no_parameters
      index(<<~RUBY)
        class Foo
          def bar
          end
        end
      RUBY

      assert_entry("bar", Entry::InstanceMethod, "/fake/path/foo.rb:1-2:2-5", "Foo")
    end

    def test_top_level_method
      index(<<~RUBY)
        def bar
        end
      RUBY

      assert_entry("bar", Entry::InstanceMethod, "/fake/path/foo.rb:0-0:1-3", nil)
    end

    def test_module_method_with_no_parameters
      index(<<~RUBY)
        module Foo
          def bar
          end
        end
      RUBY

      assert_entry("bar", Entry::InstanceMethod, "/fake/path/foo.rb:1-2:2-5", "Foo")
    end

    def test_singleton_method_using_class_self
      index(<<~RUBY)
        class Foo
          class << self
            def bar
            end
          end

          def baz
          end
        end
      RUBY

      assert_entry("bar", Entry::SingletonMethod, "/fake/path/foo.rb:2-4:3-7", "Foo")
      assert_entry("baz", Entry::InstanceMethod, "/fake/path/foo.rb:6-2:7-5", "Foo")
    end

    def test_singleton_method_using_class_self_with_nesting
      index(<<~RUBY)
        class Foo
          class << self
            class Nested
              def bar
              end
            end
          end
        end
      RUBY

      # TODO: I think this isn't correct
      assert_entry("bar", Entry::SingletonMethod, "/fake/path/foo.rb:3-6:4-9", "Foo::Nested")
    end

    def test_singleton_method_using_class
      index(<<~RUBY)
        class Foo
          def self.bar
          end
        end
      RUBY

      assert_entry("bar", Entry::SingletonMethod, "/fake/path/foo.rb:1-2:2-5", "Foo")
    end

    def test_singleton_method_using_other_receiver_is_not_indexed
      index(<<~RUBY)
        class Foo
          def String.bar
          end
        end
      RUBY

      assert_no_entry("bar")
    end

    def test_method_with_parameters
      index(<<~RUBY)
        class Foo
          def bar(a)
          end
        end
      RUBY

      assert_entry("bar", Entry::InstanceMethod, "/fake/path/foo.rb:1-2:2-5", "Foo")
      entry = T.must(@index["bar"].first)
      assert_equal(1, entry.parameters.length)
      parameter = entry.parameters.first
      assert_equal(:a, parameter.name)
      assert_instance_of(Entry::RequiredParameter, parameter)
    end

    def test_method_with_destructed_parameters
      index(<<~RUBY)
        class Foo
          def bar((a, (b, )))
          end
        end
      RUBY

      assert_entry("bar", Entry::InstanceMethod, "/fake/path/foo.rb:1-2:2-5", "Foo")
      entry = T.must(@index["bar"].first)
      assert_equal(1, entry.parameters.length)
      parameter = entry.parameters.first
      assert_equal(:"(a, (b, ))", parameter.name)
      assert_instance_of(Entry::RequiredParameter, parameter)
    end
  end
end
