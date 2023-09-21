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

    def test_indexing_constant_aliases
      index(<<~RUBY)
        module A
          module B
            module C
            end
          end

          FIRST = B::C
        end

        SECOND = A::FIRST
      RUBY

      unresolve_entry = @index["A::FIRST"].first
      assert_instance_of(Index::Entry::UnresolvedAlias, unresolve_entry)
      assert_equal(["A"], unresolve_entry.nesting)
      assert_equal("B::C", unresolve_entry.target)

      resolved_entry = @index.resolve("A::FIRST", []).first
      assert_instance_of(Index::Entry::Alias, resolved_entry)
      assert_equal("A::B::C", resolved_entry.target)
    end

    def test_aliasing_namespaces
      index(<<~RUBY)
        module A
          module B
            module C
            end
          end

          ALIAS = B
        end

        module Other
          ONE_MORE = A::ALIAS
        end
      RUBY

      unresolve_entry = @index["A::ALIAS"].first
      assert_instance_of(Index::Entry::UnresolvedAlias, unresolve_entry)
      assert_equal(["A"], unresolve_entry.nesting)
      assert_equal("B", unresolve_entry.target)

      resolved_entry = @index.resolve("ALIAS", ["A"]).first
      assert_instance_of(Index::Entry::Alias, resolved_entry)
      assert_equal("A::B", resolved_entry.target)

      resolved_entry = @index.resolve("ALIAS::C", ["A"]).first
      assert_instance_of(Index::Entry::Module, resolved_entry)
      assert_equal("A::B::C", resolved_entry.name)

      unresolve_entry = @index["Other::ONE_MORE"].first
      assert_instance_of(Index::Entry::UnresolvedAlias, unresolve_entry)
      assert_equal(["Other"], unresolve_entry.nesting)
      assert_equal("A::ALIAS", unresolve_entry.target)

      resolved_entry = @index.resolve("Other::ONE_MORE::C", []).first
      assert_instance_of(Index::Entry::Module, resolved_entry)
    end

    def test_indexing_same_line_constant_aliases
      index(<<~RUBY)
        module A
          B = C = 1
          D = E ||= 1
          F = G::H &&= 1
          I::J = K::L = M = 1
        end
      RUBY

      # B and C
      unresolve_entry = @index["A::B"].first
      assert_instance_of(Index::Entry::UnresolvedAlias, unresolve_entry)
      assert_equal(["A"], unresolve_entry.nesting)
      assert_equal("C", unresolve_entry.target)

      resolved_entry = @index.resolve("A::B", []).first
      assert_instance_of(Index::Entry::Alias, resolved_entry)
      assert_equal("A::C", resolved_entry.target)

      constant = @index["A::C"].first
      assert_instance_of(Index::Entry::Constant, constant)

      # D and E
      unresolve_entry = @index["A::D"].first
      assert_instance_of(Index::Entry::UnresolvedAlias, unresolve_entry)
      assert_equal(["A"], unresolve_entry.nesting)
      assert_equal("E", unresolve_entry.target)

      resolved_entry = @index.resolve("A::D", []).first
      assert_instance_of(Index::Entry::Alias, resolved_entry)
      assert_equal("A::E", resolved_entry.target)

      # F and G::H
      unresolve_entry = @index["A::F"].first
      assert_instance_of(Index::Entry::UnresolvedAlias, unresolve_entry)
      assert_equal(["A"], unresolve_entry.nesting)
      assert_equal("G::H", unresolve_entry.target)

      resolved_entry = @index.resolve("A::F", []).first
      assert_instance_of(Index::Entry::Alias, resolved_entry)
      assert_equal("A::G::H", resolved_entry.target)

      # I::J, K::L and M
      unresolve_entry = @index["A::I::J"].first
      assert_instance_of(Index::Entry::UnresolvedAlias, unresolve_entry)
      assert_equal(["A"], unresolve_entry.nesting)
      assert_equal("K::L", unresolve_entry.target)

      resolved_entry = @index.resolve("A::I::J", []).first
      assert_instance_of(Index::Entry::Alias, resolved_entry)
      assert_equal("A::K::L", resolved_entry.target)

      # When we are resolving A::I::J, we invoke `resolve("K::L", ["A"])`, which recursively resolves A::K::L too.
      # Therefore, both A::I::J and A::K::L point to A::M by the end of the previous resolve invocation
      resolved_entry = @index["A::K::L"].first
      assert_instance_of(Index::Entry::Alias, resolved_entry)
      assert_equal("A::M", resolved_entry.target)

      constant = @index["A::M"].first
      assert_instance_of(Index::Entry::Constant, constant)
    end
  end
end
