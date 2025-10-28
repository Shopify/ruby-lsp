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

        BAR = 3 if condition
      RUBY

      assert_entry("FOO", Entry::Constant, "/fake/path/foo.rb:0-0:0-7")
      assert_entry("Bar::FOO", Entry::Constant, "/fake/path/foo.rb:3-2:3-9")
      assert_entry("BAR", Entry::Constant, "/fake/path/foo.rb:6-0:6-7")
    end

    def test_constant_with_multibyte_characters
      index(<<~RUBY)
        CONST_💎 = "Ruby"
      RUBY

      assert_entry("CONST_💎", Entry::Constant, "/fake/path/foo.rb:0-0:0-16")
    end

    def test_constant_or_writes
      index(<<~RUBY)
        FOO ||= 1

        class ::Bar
          FOO ||= 2
        end
      RUBY

      assert_entry("FOO", Entry::Constant, "/fake/path/foo.rb:0-0:0-9")
      assert_entry("Bar::FOO", Entry::Constant, "/fake/path/foo.rb:3-2:3-11")
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

      assert_entry("A::FOO", Entry::Constant, "/fake/path/foo.rb:1-2:1-9")
      assert_entry("BAR", Entry::Constant, "/fake/path/foo.rb:2-2:2-11")
      assert_entry("A::B::FOO", Entry::Constant, "/fake/path/foo.rb:5-4:5-11")
      assert_entry("A::BAZ", Entry::Constant, "/fake/path/foo.rb:9-0:9-10")
    end

    def test_constant_path_or_writes
      index(<<~RUBY)
        class A
          FOO ||= 1
          ::BAR ||= 1
        end

        A::BAZ ||= 1
      RUBY

      assert_entry("A::FOO", Entry::Constant, "/fake/path/foo.rb:1-2:1-11")
      assert_entry("BAR", Entry::Constant, "/fake/path/foo.rb:2-2:2-13")
      assert_entry("A::BAZ", Entry::Constant, "/fake/path/foo.rb:5-0:5-12")
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

      foo = @index["FOO"]&.first #: as !nil
      assert_equal("FOO comment", foo.comments)

      a_foo = @index["A::FOO"]&.first #: as !nil
      assert_equal("A::FOO comment", a_foo.comments)

      bar = @index["BAR"]&.first #: as !nil
      assert_equal("::BAR comment", bar.comments)

      a_baz = @index["A::BAZ"]&.first #: as !nil
      assert_equal("A::BAZ comment", a_baz.comments)
    end

    def test_variable_path_constants_are_ignored
      index(<<~RUBY)
        var::FOO = 1
        self.class::FOO = 1
      RUBY

      assert_no_indexed_entries
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

      b_const = @index["A::B"]&.first #: as !nil
      assert_predicate(b_const, :private?)

      c_const = @index["A::C"]&.first #: as !nil
      assert_predicate(c_const, :private?)

      d_const = @index["A::D"]&.first #: as !nil
      assert_predicate(d_const, :public?)
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

      a_const = @index["A::B::CONST_A"]&.first #: as !nil
      assert_predicate(a_const, :private?)

      b_const = @index["A::B::CONST_B"]&.first #: as !nil
      assert_predicate(b_const, :private?)

      c_const = @index["A::B::CONST_C"]&.first #: as !nil
      assert_predicate(c_const, :private?)
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

      a_const = @index["A::B::CONST_A"]&.first #: as !nil
      assert_predicate(a_const, :private?)

      b_const = @index["A::B::CONST_B"]&.first #: as !nil
      assert_predicate(b_const, :private?)
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

      unresolve_entry = @index["A::FIRST"]&.first #: as Entry::UnresolvedConstantAlias
      assert_instance_of(Entry::UnresolvedConstantAlias, unresolve_entry)
      assert_equal(["A"], unresolve_entry.nesting)
      assert_equal("B::C", unresolve_entry.target)

      resolved_entry = @index.resolve("A::FIRST", [])&.first #: as Entry::ConstantAlias
      assert_instance_of(Entry::ConstantAlias, resolved_entry)
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

      unresolve_entry = @index["A::ALIAS"]&.first #: as Entry::UnresolvedConstantAlias
      assert_instance_of(Entry::UnresolvedConstantAlias, unresolve_entry)
      assert_equal(["A"], unresolve_entry.nesting)
      assert_equal("B", unresolve_entry.target)

      resolved_entry = @index.resolve("ALIAS", ["A"])&.first #: as Entry::ConstantAlias
      assert_instance_of(Entry::ConstantAlias, resolved_entry)
      assert_equal("A::B", resolved_entry.target)

      resolved_entry = @index.resolve("ALIAS::C", ["A"])&.first #: as Entry::Module
      assert_instance_of(Entry::Module, resolved_entry)
      assert_equal("A::B::C", resolved_entry.name)

      unresolve_entry = @index["Other::ONE_MORE"]&.first #: as Entry::UnresolvedConstantAlias
      assert_instance_of(Entry::UnresolvedConstantAlias, unresolve_entry)
      assert_equal(["Other"], unresolve_entry.nesting)
      assert_equal("A::ALIAS", unresolve_entry.target)

      resolved_entry = @index.resolve("Other::ONE_MORE::C", [])&.first
      assert_instance_of(Entry::Module, resolved_entry)
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
      unresolve_entry = @index["A::B"]&.first #: as Entry::UnresolvedConstantAlias
      assert_instance_of(Entry::UnresolvedConstantAlias, unresolve_entry)
      assert_equal(["A"], unresolve_entry.nesting)
      assert_equal("C", unresolve_entry.target)

      resolved_entry = @index.resolve("A::B", [])&.first #: as Entry::ConstantAlias
      assert_instance_of(Entry::ConstantAlias, resolved_entry)
      assert_equal("A::C", resolved_entry.target)

      constant = @index["A::C"]&.first #: as Entry::Constant
      assert_instance_of(Entry::Constant, constant)

      # D and E
      unresolve_entry = @index["A::D"]&.first #: as Entry::UnresolvedConstantAlias
      assert_instance_of(Entry::UnresolvedConstantAlias, unresolve_entry)
      assert_equal(["A"], unresolve_entry.nesting)
      assert_equal("E", unresolve_entry.target)

      resolved_entry = @index.resolve("A::D", [])&.first #: as Entry::ConstantAlias
      assert_instance_of(Entry::ConstantAlias, resolved_entry)
      assert_equal("A::E", resolved_entry.target)

      # F and G::H
      unresolve_entry = @index["A::F"]&.first #: as Entry::UnresolvedConstantAlias
      assert_instance_of(Entry::UnresolvedConstantAlias, unresolve_entry)
      assert_equal(["A"], unresolve_entry.nesting)
      assert_equal("G::H", unresolve_entry.target)

      resolved_entry = @index.resolve("A::F", [])&.first #: as Entry::ConstantAlias
      assert_instance_of(Entry::ConstantAlias, resolved_entry)
      assert_equal("A::G::H", resolved_entry.target)

      # I::J, K::L and M
      unresolve_entry = @index["A::I::J"]&.first #: as Entry::UnresolvedConstantAlias
      assert_instance_of(Entry::UnresolvedConstantAlias, unresolve_entry)
      assert_equal(["A"], unresolve_entry.nesting)
      assert_equal("K::L", unresolve_entry.target)

      resolved_entry = @index.resolve("A::I::J", [])&.first #: as Entry::ConstantAlias
      assert_instance_of(Entry::ConstantAlias, resolved_entry)
      assert_equal("A::K::L", resolved_entry.target)

      # When we are resolving A::I::J, we invoke `resolve("K::L", ["A"])`, which recursively resolves A::K::L too.
      # Therefore, both A::I::J and A::K::L point to A::M by the end of the previous resolve invocation
      resolved_entry = @index["A::K::L"]&.first #: as Entry::ConstantAlias
      assert_instance_of(Entry::ConstantAlias, resolved_entry)
      assert_equal("A::M", resolved_entry.target)

      constant = @index["A::M"]&.first
      assert_instance_of(Entry::Constant, constant)
    end

    def test_indexing_or_and_operator_nodes
      index(<<~RUBY)
        A ||= 1
        B &&= 2
        C &= 3
        D::E ||= 4
        F::G &&= 5
        H::I &= 6
      RUBY

      assert_entry("A", Entry::Constant, "/fake/path/foo.rb:0-0:0-7")
      assert_entry("B", Entry::Constant, "/fake/path/foo.rb:1-0:1-7")
      assert_entry("C", Entry::Constant, "/fake/path/foo.rb:2-0:2-6")
      assert_entry("D::E", Entry::Constant, "/fake/path/foo.rb:3-0:3-10")
      assert_entry("F::G", Entry::Constant, "/fake/path/foo.rb:4-0:4-10")
      assert_entry("H::I", Entry::Constant, "/fake/path/foo.rb:5-0:5-9")
    end

    def test_indexing_constant_targets
      index(<<~RUBY)
        module A
          B, C = [1, Y]
          D::E, F::G = [Z, 4]
          H, I::J = [5, B]
          K, L = C
        end

        module Real
          Z = 1
          Y = 2
        end
      RUBY

      assert_entry("A::B", Entry::Constant, "/fake/path/foo.rb:1-2:1-3")
      assert_entry("A::C", Entry::UnresolvedConstantAlias, "/fake/path/foo.rb:1-5:1-6")
      assert_entry("A::D::E", Entry::UnresolvedConstantAlias, "/fake/path/foo.rb:2-2:2-6")
      assert_entry("A::F::G", Entry::Constant, "/fake/path/foo.rb:2-8:2-12")
      assert_entry("A::H", Entry::Constant, "/fake/path/foo.rb:3-2:3-3")
      assert_entry("A::I::J", Entry::UnresolvedConstantAlias, "/fake/path/foo.rb:3-5:3-9")
      assert_entry("A::K", Entry::Constant, "/fake/path/foo.rb:4-2:4-3")
      assert_entry("A::L", Entry::Constant, "/fake/path/foo.rb:4-5:4-6")
    end

    def test_indexing_constant_targets_with_splats
      index(<<~RUBY)
        A, *, B = baz
        C, = bar
        (D, E) = baz
        F, G = *baz, qux
        H, I = [baz, *qux]
        J, L = [*something, String]
        M = [String]
      RUBY

      assert_entry("A", Entry::Constant, "/fake/path/foo.rb:0-0:0-1")
      assert_entry("B", Entry::Constant, "/fake/path/foo.rb:0-6:0-7")
      assert_entry("D", Entry::Constant, "/fake/path/foo.rb:2-1:2-2")
      assert_entry("E", Entry::Constant, "/fake/path/foo.rb:2-4:2-5")
      assert_entry("F", Entry::Constant, "/fake/path/foo.rb:3-0:3-1")
      assert_entry("G", Entry::Constant, "/fake/path/foo.rb:3-3:3-4")
      assert_entry("H", Entry::Constant, "/fake/path/foo.rb:4-0:4-1")
      assert_entry("I", Entry::Constant, "/fake/path/foo.rb:4-3:4-4")
      assert_entry("J", Entry::Constant, "/fake/path/foo.rb:5-0:5-1")
      assert_entry("L", Entry::Constant, "/fake/path/foo.rb:5-3:5-4")
      assert_entry("M", Entry::Constant, "/fake/path/foo.rb:6-0:6-12")
    end

    def test_indexing_destructuring_an_array
      index(<<~RUBY)
        Baz = [1, 2]
        Foo, Bar = Baz
        This, That = foo, bar
      RUBY

      assert_entry("Baz", Entry::Constant, "/fake/path/foo.rb:0-0:0-12")
      assert_entry("Foo", Entry::Constant, "/fake/path/foo.rb:1-0:1-3")
      assert_entry("Bar", Entry::Constant, "/fake/path/foo.rb:1-5:1-8")
      assert_entry("This", Entry::Constant, "/fake/path/foo.rb:2-0:2-4")
      assert_entry("That", Entry::Constant, "/fake/path/foo.rb:2-6:2-10")
    end
  end
end
