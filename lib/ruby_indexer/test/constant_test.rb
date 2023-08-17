# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class ConstantTest < TestCase
    def test_constant_writes
      index(<<~RUBY)
        FOO = 1

        class ::Bar
          FOO = 2
        end
      RUBY

      assert_entry("FOO", Index::Entry::Constant, "/fake/path/foo.rb:0-0:0-6")
      assert_entry("Bar::FOO", Index::Entry::Constant, "/fake/path/foo.rb:3-2:3-8")
    end

    def test_constant_or_writes
      index(<<~RUBY)
        FOO ||= 1

        class ::Bar
          FOO ||= 2
        end
      RUBY

      assert_entry("FOO", Index::Entry::Constant, "/fake/path/foo.rb:0-0:0-8")
      assert_entry("Bar::FOO", Index::Entry::Constant, "/fake/path/foo.rb:3-2:3-10")
    end

    def test_constant_path_writes
      index(<<~RUBY)
        class A
          FOO = 1
          ::BAR = 1

          module B
            FOO = 1
          end
        end

        A::BAZ = 1
      RUBY

      assert_entry("A::FOO", Index::Entry::Constant, "/fake/path/foo.rb:1-2:1-8")
      assert_entry("BAR", Index::Entry::Constant, "/fake/path/foo.rb:2-2:2-10")
      assert_entry("A::B::FOO", Index::Entry::Constant, "/fake/path/foo.rb:5-4:5-10")
      assert_entry("A::BAZ", Index::Entry::Constant, "/fake/path/foo.rb:9-0:9-9")
    end

    def test_constant_path_or_writes
      index(<<~RUBY)
        class A
          FOO ||= 1
          ::BAR ||= 1
        end

        A::BAZ ||= 1
      RUBY

      assert_entry("A::FOO", Index::Entry::Constant, "/fake/path/foo.rb:1-2:1-10")
      assert_entry("BAR", Index::Entry::Constant, "/fake/path/foo.rb:2-2:2-12")
      assert_entry("A::BAZ", Index::Entry::Constant, "/fake/path/foo.rb:5-0:5-11")
    end

    def test_comments_for_constants
      index(<<~RUBY)
        # FOO comment
        FOO = 1

        class A
          # A::FOO comment
          FOO = 1

          # ::BAR comment
          ::BAR = 1
        end

        # A::BAZ comment
        A::BAZ = 1
      RUBY

      foo_comment = @index["FOO"].first.comments.join("\n")
      assert_equal("# FOO comment\n", foo_comment)

      a_foo_comment = @index["A::FOO"].first.comments.join("\n")
      assert_equal("# A::FOO comment\n", a_foo_comment)

      bar_comment = @index["BAR"].first.comments.join("\n")
      assert_equal("# ::BAR comment\n", bar_comment)

      a_baz_comment = @index["A::BAZ"].first.comments.join("\n")
      assert_equal("# A::BAZ comment\n", a_baz_comment)
    end

    def test_variable_path_constants_are_ignored
      index(<<~RUBY)
        var::FOO = 1
        self.class::FOO = 1
      RUBY

      assert_no_entry
    end
  end
end
