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

      assert_entry("bar", Entry::InstanceMethod, "/fake/path/foo.rb:1-2:2-5")
    end

    def test_singleton_method_using_self_receiver
      index(<<~RUBY)
        class Foo
          def self.bar
          end
        end
      RUBY

      assert_entry("bar", Entry::SingletonMethod, "/fake/path/foo.rb:1-2:2-5")
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

      assert_entry("bar", Entry::InstanceMethod, "/fake/path/foo.rb:1-2:2-5")
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

      assert_entry("bar", Entry::InstanceMethod, "/fake/path/foo.rb:1-2:2-5")
      entry = T.must(@index["bar"].first)
      assert_equal(1, entry.parameters.length)
      parameter = entry.parameters.first
      assert_equal(:"(a, (b, ))", parameter.name)
      assert_instance_of(Entry::RequiredParameter, parameter)
    end

    def test_keeps_track_of_method_owner
      index(<<~RUBY)
        class Foo
          def bar
          end
        end
      RUBY

      entry = T.must(@index["bar"].first)
      owner_name = T.must(entry.owner).name

      assert_equal("Foo", owner_name)
    end

    def test_keeps_track_of_attributes
      index(<<~RUBY)
        class Foo
          # Hello there
          attr_reader :bar, :other
          attr_writer :baz
          attr_accessor :qux
        end
      RUBY

      assert_entry("bar", Entry::Attribute, "/fake/path/foo.rb:2-15:2-18")
      assert_equal("Hello there", @index["bar"].first.comments.join("\n"))
      assert_entry("other", Entry::Attribute, "/fake/path/foo.rb:2-21:2-26")
      assert_equal("Hello there", @index["other"].first.comments.join("\n"))
      assert_entry("baz=", Entry::Attribute, "/fake/path/foo.rb:3-15:3-18")
      assert_entry("qux", Entry::Attribute, "/fake/path/foo.rb:4-17:4-20")
      assert_entry("qux=", Entry::Attribute, "/fake/path/foo.rb:4-17:4-20")
    end
  end
end
