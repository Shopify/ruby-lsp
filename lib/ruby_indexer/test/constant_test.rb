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

      assert_entry("FOO", Index::Entry::Constant, "/fake/path/foo.rb:0-0:0-7")
      assert_entry("Bar::FOO", Index::Entry::Constant, "/fake/path/foo.rb:3-2:3-9")
    end

    def test_constant_or_writes
      index(<<~RUBY)
        FOO ||= 1

        class ::Bar
          FOO ||= 2
        end
      RUBY

      assert_entry("FOO", Index::Entry::Constant, "/fake/path/foo.rb:0-0:0-9")
      assert_entry("Bar::FOO", Index::Entry::Constant, "/fake/path/foo.rb:3-2:3-11")
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

      assert_entry("A::FOO", Index::Entry::Constant, "/fake/path/foo.rb:1-2:1-9")
      assert_entry("BAR", Index::Entry::Constant, "/fake/path/foo.rb:2-2:2-11")
      assert_entry("A::B::FOO", Index::Entry::Constant, "/fake/path/foo.rb:5-4:5-11")
      assert_entry("A::BAZ", Index::Entry::Constant, "/fake/path/foo.rb:9-0:9-10")
    end

    def test_constant_path_or_writes
      index(<<~RUBY)
        class A
          FOO ||= 1
          ::BAR ||= 1
        end

        A::BAZ ||= 1
      RUBY

      assert_entry("A::FOO", Index::Entry::Constant, "/fake/path/foo.rb:1-2:1-11")
      assert_entry("BAR", Index::Entry::Constant, "/fake/path/foo.rb:2-2:2-13")
      assert_entry("A::BAZ", Index::Entry::Constant, "/fake/path/foo.rb:5-0:5-12")
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
      assert_equal("FOO comment", foo_comment)

      a_foo_comment = @index["A::FOO"].first.comments.join("\n")
      assert_equal("A::FOO comment", a_foo_comment)

      bar_comment = @index["BAR"].first.comments.join("\n")
      assert_equal("::BAR comment", bar_comment)

      a_baz_comment = @index["A::BAZ"].first.comments.join("\n")
      assert_equal("A::BAZ comment", a_baz_comment)
    end

    def test_variable_path_constants_are_ignored
      index(<<~RUBY)
        var::FOO = 1
        self.class::FOO = 1
      RUBY

      assert_no_entry
    end

    def test_private_constant_indexing
      index(<<~RUBY)
        class A
          B = 1
          private_constant(:B)

          C = 2
          private_constant("C")

          D = 1
        end
      RUBY

      b_const = @index["A::B"].first
      assert_equal(:private, b_const.visibility)

      c_const = @index["A::C"].first
      assert_equal(:private, c_const.visibility)

      d_const = @index["A::D"].first
      assert_equal(:public, d_const.visibility)
    end

    def test_marking_constants_as_private_reopening_namespaces
      index(<<~RUBY)
        module A
          module B
            CONST_A = 1
            private_constant(:CONST_A)

            CONST_B = 2
            CONST_C = 3
          end

          module B
            private_constant(:CONST_B)
          end
        end

        module A
          module B
            private_constant(:CONST_C)
          end
        end
      RUBY

      a_const = @index["A::B::CONST_A"].first
      assert_equal(:private, a_const.visibility)

      b_const = @index["A::B::CONST_B"].first
      assert_equal(:private, b_const.visibility)

      c_const = @index["A::B::CONST_C"].first
      assert_equal(:private, c_const.visibility)
    end

    def test_marking_constants_as_private_with_receiver
      index(<<~RUBY)
        module A
          module B
            CONST_A = 1
            CONST_B = 2
          end

          B.private_constant(:CONST_A)
        end

        A::B.private_constant(:CONST_B)
      RUBY

      a_const = @index["A::B::CONST_A"].first
      assert_equal(:private, a_const.visibility)

      b_const = @index["A::B::CONST_B"].first
      assert_equal(:private, b_const.visibility)
    end
  end
end
