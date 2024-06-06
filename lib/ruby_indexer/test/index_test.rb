# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class IndexTest < TestCase
    def test_deleting_one_entry_for_a_class
      @index.index_single(IndexablePath.new(nil, "/fake/path/foo.rb"), <<~RUBY)
        class Foo
        end
      RUBY
      @index.index_single(IndexablePath.new(nil, "/fake/path/other_foo.rb"), <<~RUBY)
        class Foo
        end
      RUBY

      entries = @index["Foo"]
      assert_equal(2, entries.length)

      @index.delete(IndexablePath.new(nil, "/fake/path/other_foo.rb"))
      entries = @index["Foo"]
      assert_equal(1, entries.length)
    end

    def test_deleting_all_entries_for_a_class
      @index.index_single(IndexablePath.new(nil, "/fake/path/foo.rb"), <<~RUBY)
        class Foo
        end
      RUBY

      entries = @index["Foo"]
      assert_equal(1, entries.length)

      @index.delete(IndexablePath.new(nil, "/fake/path/foo.rb"))
      entries = @index["Foo"]
      assert_nil(entries)
    end

    def test_index_resolve
      @index.index_single(IndexablePath.new(nil, "/fake/path/foo.rb"), <<~RUBY)
        class Bar; end

        module Foo
          class Bar
          end

          class Baz
            class Something
            end
          end
        end
      RUBY

      entries = @index.resolve("Something", ["Foo", "Baz"])
      refute_empty(entries)
      assert_equal("Foo::Baz::Something", entries.first.name)

      entries = @index.resolve("Bar", ["Foo"])
      refute_empty(entries)
      assert_equal("Foo::Bar", entries.first.name)

      entries = @index.resolve("Bar", ["Foo", "Baz"])
      refute_empty(entries)
      assert_equal("Foo::Bar", entries.first.name)

      entries = @index.resolve("Foo::Bar", ["Foo", "Baz"])
      refute_empty(entries)
      assert_equal("Foo::Bar", entries.first.name)

      assert_nil(@index.resolve("DoesNotExist", ["Foo"]))
    end

    def test_accessing_with_colon_colon_prefix
      @index.index_single(IndexablePath.new(nil, "/fake/path/foo.rb"), <<~RUBY)
        class Bar; end

        module Foo
          class Bar
          end

          class Baz
            class Something
            end
          end
        end
      RUBY

      entries = @index["::Foo::Baz::Something"]
      refute_empty(entries)
      assert_equal("Foo::Baz::Something", entries.first.name)
    end

    def test_fuzzy_search
      @index.index_single(IndexablePath.new(nil, "/fake/path/foo.rb"), <<~RUBY)
        class Bar; end

        module Foo
          class Bar
          end

          class Baz
            class Something
            end
          end
        end
      RUBY

      result = @index.fuzzy_search("Bar")
      assert_equal(3, result.length)
      assert_equal(["Bar", "Backtrace", "Base"], result.map(&:name))

      result = @index.fuzzy_search("foobarsomeking")
      assert_equal(6, result.length)
      assert_equal(["Foo::Baz::Something", "Foo::Bar", "Foo::Baz", "Foo", "Base", "Bar"], result.map(&:name))

      result = @index.fuzzy_search("FooBaz")
      assert_equal(5, result.length)
      assert_equal(["Foo::Baz", "Foo::Bar", "Foo", "Foo::Baz::Something", "Float"], result.map(&:name))
    end

    def test_index_single_ignores_directories
      FileUtils.mkdir("lib/this_is_a_dir.rb")
      @index.index_single(IndexablePath.new(nil, "lib/this_is_a_dir.rb"))
    ensure
      FileUtils.rm_r("lib/this_is_a_dir.rb")
    end

    def test_searching_for_require_paths
      @index.index_single(IndexablePath.new("/fake", "/fake/path/foo.rb"), <<~RUBY)
        class Foo
        end
      RUBY
      @index.index_single(IndexablePath.new("/fake", "/fake/path/other_foo.rb"), <<~RUBY)
        class Foo
        end
      RUBY

      assert_equal(["path/foo", "path/other_foo"], @index.search_require_paths("path").map(&:require_path))
    end

    def test_searching_for_entries_based_on_prefix
      # For this test, it's easier if we don't include core classes and modules
      @index = Index.new
      @index.index_single(IndexablePath.new("/fake", "/fake/path/foo.rb"), <<~RUBY)
        class Foo::Bar
        end
      RUBY
      @index.index_single(IndexablePath.new("/fake", "/fake/path/other_foo.rb"), <<~RUBY)
        class Foo::Bar
        end

        class Foo::Baz
        end
      RUBY

      results = @index.prefix_search("Foo", []).map { |entries| entries.map(&:name) }
      assert_equal([["Foo::Bar", "Foo::Bar"], ["Foo::Baz"]], results)

      results = @index.prefix_search("Ba", ["Foo"]).map { |entries| entries.map(&:name) }
      assert_equal([["Foo::Bar", "Foo::Bar"], ["Foo::Baz"]], results)
    end

    def test_resolve_normalizes_top_level_names
      @index.index_single(IndexablePath.new("/fake", "/fake/path/foo.rb"), <<~RUBY)
        class Bar; end

        module Foo
          class Bar; end
        end
      RUBY

      entries = @index.resolve("::Foo::Bar", [])
      refute_nil(entries)

      assert_equal("Foo::Bar", entries.first.name)

      entries = @index.resolve("::Bar", ["Foo"])
      refute_nil(entries)

      assert_equal("Bar", entries.first.name)
    end

    def test_resolving_aliases_to_non_existing_constants_with_conflicting_names
      @index.index_single(IndexablePath.new("/fake", "/fake/path/foo.rb"), <<~RUBY)
        class Float
        end

        module Foo
          class Float < self
            INFINITY = ::Float::INFINITY
          end
        end
      RUBY

      entry = @index.resolve("INFINITY", ["Foo", "Float"]).first
      refute_nil(entry)

      assert_instance_of(Entry::UnresolvedAlias, entry)
    end

    def test_visitor_does_not_visit_unnecessary_nodes
      concats = (0...10_000).map do |i|
        <<~STRING
          "string#{i}" \\
        STRING
      end.join

      index(<<~RUBY)
        module Foo
          local_var = #{concats}
            "final"
          @class_instance_var = #{concats}
            "final"
          @@class_var = #{concats}
            "final"
          $global_var = #{concats}
            "final"
          CONST = #{concats}
            "final"
        end
      RUBY
    end

    def test_resolve_method_with_known_receiver
      index(<<~RUBY)
        module Foo
          module Bar
            def baz; end
          end
        end
      RUBY

      entries = T.must(@index.resolve_method("baz", "Foo::Bar"))
      assert_equal("baz", entries.first.name)
      assert_equal("Foo::Bar", T.must(entries.first.owner).name)
    end

    def test_resolve_method_with_class_name_conflict
      index(<<~RUBY)
        class Array
        end

        class Foo
          def Array(*args); end
        end
      RUBY

      entries = T.must(@index.resolve_method("Array", "Foo"))
      assert_equal("Array", entries.first.name)
      assert_equal("Foo", T.must(entries.first.owner).name)
    end

    def test_resolve_method_attribute
      index(<<~RUBY)
        class Foo
          attr_reader :bar
        end
      RUBY

      entries = T.must(@index.resolve_method("bar", "Foo"))
      assert_equal("bar", entries.first.name)
      assert_equal("Foo", T.must(entries.first.owner).name)
    end

    def test_resolve_method_with_two_definitions
      index(<<~RUBY)
        class Foo
          # Hello from first `bar`
          def bar; end
        end

        class Foo
          # Hello from second `bar`
          def bar; end
        end
      RUBY

      first_entry, second_entry = T.must(@index.resolve_method("bar", "Foo"))

      assert_equal("bar", first_entry.name)
      assert_equal("Foo", T.must(first_entry.owner).name)
      assert_includes(first_entry.comments, "Hello from first `bar`")

      assert_equal("bar", second_entry.name)
      assert_equal("Foo", T.must(second_entry.owner).name)
      assert_includes(second_entry.comments, "Hello from second `bar`")
    end

    def test_prefix_search_for_methods
      index(<<~RUBY)
        module Foo
          module Bar
            def baz; end
          end
        end
      RUBY

      entries = @index.prefix_search("ba")
      refute_empty(entries)

      entry = T.must(entries.first).first
      assert_equal("baz", entry.name)
    end

    def test_indexing_prism_fixtures_succeeds
      unless Dir.exist?("test/fixtures/prism/test/prism/fixtures")
        raise "Prism fixtures not found. Run `git submodule update --init` to fetch them."
      end

      fixtures = Dir.glob("test/fixtures/prism/test/prism/fixtures/**/*.txt")

      fixtures.each do |fixture|
        indexable_path = IndexablePath.new("", fixture)
        @index.index_single(indexable_path)
      end

      refute_empty(@index.instance_variable_get(:@entries))
    end

    def test_index_single_does_not_fail_for_non_existing_file
      @index.index_single(IndexablePath.new(nil, "/fake/path/foo.rb"))
      entries_after_indexing = @index.instance_variable_get(:@entries).keys
      assert_equal(@default_indexed_entries.keys, entries_after_indexing)
    end

    def test_linearized_ancestors_basic_ordering
      index(<<~RUBY)
        module A; end
        module B; end

        class Foo
          prepend A
          prepend B
        end

        class Bar
          include A
          include B
        end
      RUBY

      assert_equal(
        [
          "B",
          "A",
          "Foo",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Foo"),
      )

      assert_equal(
        [
          "Bar",
          "B",
          "A",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Bar"),
      )
    end

    def test_linearized_ancestors
      index(<<~RUBY)
        module A; end
        module B; end
        module C; end

        module D
          include A
        end

        module E
          prepend B
        end

        module F
          include C
          include A
        end

        class Bar
          prepend F
        end

        class Foo < Bar
          include E
          prepend D
        end
      RUBY

      # Object, Kernel and BasicObject are intentionally commented out for now until we develop a strategy for indexing
      # declarations made in C code
      assert_equal(
        [
          "D",
          "A",
          "Foo",
          "B",
          "E",
          "F",
          "A",
          "C",
          "Bar",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Foo"),
      )
    end

    def test_linearized_ancestors_duplicates
      index(<<~RUBY)
        module A; end
        module B
          include A
        end

        class Foo
          include B
          include A
        end

        class Bar
          prepend B
          prepend A
        end
      RUBY

      assert_equal(
        [
          "Foo",
          "B",
          "A",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Foo"),
      )

      assert_equal(
        [
          "B",
          "A",
          "Bar",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Bar"),
      )
    end

    def test_linearizing_ancestors_is_cached
      index(<<~RUBY)
        module C; end
        module A; end
        module B
          include A
        end

        class Foo
          include B
          include A
        end
      RUBY

      @index.linearized_ancestors_of("Foo")
      ancestors = @index.instance_variable_get(:@ancestors)
      assert(ancestors.key?("Foo"))
      assert(ancestors.key?("A"))
      assert(ancestors.key?("B"))
      refute(ancestors.key?("C"))
    end

    def test_duplicate_prepend_include
      index(<<~RUBY)
        module A; end

        class Foo
          prepend A
          include A
        end

        class Bar
          include A
          prepend A
        end
      RUBY

      assert_equal(
        [
          "A",
          "Foo",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Foo"),
      )

      assert_equal(
        [
          "A",
          "Bar",
          "A",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Bar"),
      )
    end

    def test_linearizing_ancestors_handles_circular_parent_class
      index(<<~RUBY)
        class Foo < Foo
        end
      RUBY

      assert_equal(["Foo"], @index.linearized_ancestors_of("Foo"))
    end

    def test_ancestors_linearization_complex_prepend_duplication
      index(<<~RUBY)
        module A; end
        module B
          prepend A
        end
        module C
          prepend B
        end

        class Foo
          prepend A
          prepend C
        end
      RUBY

      assert_equal(
        [
          "A",
          "B",
          "C",
          "Foo",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Foo"),
      )
    end

    def test_ancestors_linearization_complex_include_duplication
      index(<<~RUBY)
        module A; end
        module B
          include A
        end
        module C
          include B
        end

        class Foo
          include A
          include C
        end
      RUBY

      assert_equal(
        [
          "Foo",
          "C",
          "B",
          "A",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Foo"),
      )
    end

    def test_linearizing_ancestors_that_need_to_be_resolved
      index(<<~RUBY)
        module Foo
          module Baz
          end
          module Qux
          end

          class Something; end

          class Bar < Something
            include Baz
            prepend Qux
          end
        end
      RUBY

      assert_equal(
        [
          "Foo::Qux",
          "Foo::Bar",
          "Foo::Baz",
          "Foo::Something",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Foo::Bar"),
      )
    end

    def test_linearizing_ancestors_for_non_existing_namespaces
      index(<<~RUBY)
        def Bar(a); end
      RUBY

      assert_raises(Index::NonExistingNamespaceError) do
        @index.linearized_ancestors_of("Foo")
      end

      assert_raises(Index::NonExistingNamespaceError) do
        @index.linearized_ancestors_of("Bar")
      end
    end

    def test_linearizing_circular_ancestors
      index(<<~RUBY)
        module M1
          include M2
        end

        module M2
          include M1
        end

        module A1
          include A2
        end

        module A2
          include A3
        end

        module A3
          include A1
        end

        class Foo < Foo
          include Foo
        end

        module Bar
          include Bar
        end
      RUBY

      assert_equal(["M2", "M1"], @index.linearized_ancestors_of("M2"))
      assert_equal(["A3", "A1", "A2"], @index.linearized_ancestors_of("A3"))
      assert_equal(["Foo"], @index.linearized_ancestors_of("Foo"))
      assert_equal(["Bar"], @index.linearized_ancestors_of("Bar"))
    end

    def test_linearizing_circular_aliased_dependency
      index(<<~RUBY)
        module A
        end

        ALIAS = A

        module A
          include ALIAS
        end
      RUBY

      assert_equal(["A", "ALIAS"], @index.linearized_ancestors_of("A"))
    end

    def test_resolving_an_inherited_method
      index(<<~RUBY)
        module Foo
          def baz; end
        end

        class Bar
          def qux; end
        end

        class Wow < Bar
          include Foo
        end
      RUBY

      entry = T.must(@index.resolve_method("baz", "Wow")&.first)
      assert_equal("baz", entry.name)
      assert_equal("Foo", T.must(entry.owner).name)

      entry = T.must(@index.resolve_method("qux", "Wow")&.first)
      assert_equal("qux", entry.name)
      assert_equal("Bar", T.must(entry.owner).name)
    end

    def test_resolving_an_inherited_method_lands_on_first_match
      index(<<~RUBY)
        module Foo
          def qux; end
        end

        class Bar
          def qux; end
        end

        class Wow < Bar
          prepend Foo

          def qux; end
        end
      RUBY

      entries = T.must(@index.resolve_method("qux", "Wow"))
      assert_equal(1, entries.length)

      entry = T.must(entries.first)
      assert_equal("qux", entry.name)
      assert_equal("Foo", T.must(entry.owner).name)
    end

    def test_handle_change_clears_ancestor_cache_if_tree_changed
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          # Write the original file
          File.write(File.join(dir, "foo.rb"), <<~RUBY)
            module Foo
            end

            class Bar
              include Foo
            end
          RUBY

          indexable_path = IndexablePath.new(nil, File.join(dir, "foo.rb"))
          @index.index_single(indexable_path)

          assert_equal(["Bar", "Foo", "Object", "Kernel", "BasicObject"], @index.linearized_ancestors_of("Bar"))

          # Remove include to invalidate the ancestor tree
          File.write(File.join(dir, "foo.rb"), <<~RUBY)
            module Foo
            end

            class Bar
            end
          RUBY

          @index.handle_change(indexable_path)
          assert_empty(@index.instance_variable_get(:@ancestors))
          assert_equal(["Bar", "Object", "Kernel", "BasicObject"], @index.linearized_ancestors_of("Bar"))
        end
      end
    end

    def test_handle_change_does_not_clear_ancestor_cache_if_tree_not_changed
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          # Write the original file
          File.write(File.join(dir, "foo.rb"), <<~RUBY)
            module Foo
            end

            class Bar
              include Foo
            end
          RUBY

          indexable_path = IndexablePath.new(nil, File.join(dir, "foo.rb"))
          @index.index_single(indexable_path)

          assert_equal(["Bar", "Foo", "Object", "Kernel", "BasicObject"], @index.linearized_ancestors_of("Bar"))

          # Remove include to invalidate the ancestor tree
          File.write(File.join(dir, "foo.rb"), <<~RUBY)
            module Foo
            end

            class Bar
              include Foo

              def baz; end
            end
          RUBY

          @index.handle_change(indexable_path)
          refute_empty(@index.instance_variable_get(:@ancestors))
          assert_equal(["Bar", "Foo", "Object", "Kernel", "BasicObject"], @index.linearized_ancestors_of("Bar"))
        end
      end
    end

    def test_handle_change_clears_ancestor_cache_if_parent_class_changed
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          # Write the original file
          File.write(File.join(dir, "foo.rb"), <<~RUBY)
            class Foo
            end

            class Bar < Foo
            end
          RUBY

          indexable_path = IndexablePath.new(nil, File.join(dir, "foo.rb"))
          @index.index_single(indexable_path)

          assert_equal(["Bar", "Foo", "Object", "Kernel", "BasicObject"], @index.linearized_ancestors_of("Bar"))

          # Remove include to invalidate the ancestor tree
          File.write(File.join(dir, "foo.rb"), <<~RUBY)
            class Foo
            end

            class Bar
            end
          RUBY

          @index.handle_change(indexable_path)
          assert_empty(@index.instance_variable_get(:@ancestors))
          assert_equal(["Bar", "Object", "Kernel", "BasicObject"], @index.linearized_ancestors_of("Bar"))
        end
      end
    end

    def test_resolving_inherited_constants
      index(<<~RUBY)
        module Foo
          CONST = 1
        end

        module Baz
          CONST = 2
        end

        module Qux
          include Foo
        end

        module Namespace
          CONST = 3

          include Baz

          class Bar
            include Qux
          end
        end

        CONST = 4
      RUBY

      entry = T.must(@index.resolve("CONST", ["Namespace", "Bar"])&.first)
      assert_equal(14, entry.location.start_line)
    end

    def test_resolving_inherited_alised_namespace
      index(<<~RUBY)
        module Bar
          TARGET = 123
        end

        module Foo
          CONST = Bar
        end

        module Namespace
          class Bar
            include Foo
          end
        end
      RUBY

      entry = T.must(@index.resolve("Foo::CONST::TARGET", [])&.first)
      assert_equal(2, entry.location.start_line)

      entry = T.must(@index.resolve("Namespace::Bar::CONST::TARGET", [])&.first)
      assert_equal(2, entry.location.start_line)
    end

    def test_resolving_same_constant_from_different_scopes
      index(<<~RUBY)
        module Namespace
          CONST = 123

          class Parent
            CONST = 321
          end

          class Child < Parent
          end
        end
      RUBY

      entry = T.must(@index.resolve("CONST", ["Namespace", "Child"])&.first)
      assert_equal(2, entry.location.start_line)

      entry = T.must(@index.resolve("Namespace::Child::CONST", [])&.first)
      assert_equal(5, entry.location.start_line)
    end

    def test_resolving_prepended_constants
      index(<<~RUBY)
        module Included
          CONST = 123
        end

        module Prepended
          CONST = 321
        end

        class Foo
          include Included
          prepend Prepended
        end

        class Bar
          CONST = 456
          include Included
          prepend Prepended
        end
      RUBY

      entry = T.must(@index.resolve("CONST", ["Foo"])&.first)
      assert_equal(6, entry.location.start_line)

      entry = T.must(@index.resolve("Foo::CONST", [])&.first)
      assert_equal(6, entry.location.start_line)

      entry = T.must(@index.resolve("Bar::CONST", [])&.first)
      assert_equal(15, entry.location.start_line)
    end

    def test_resolving_constants_favors_ancestors_over_top_level
      index(<<~RUBY)
        module Value1
          CONST = 1
        end

        module Value2
          CONST = 2
        end

        CONST = 3
        module First
          include Value1

          module Second
            include Value2
          end
        end
      RUBY

      entry = T.must(@index.resolve("CONST", ["First", "Second"])&.first)
      assert_equal(6, entry.location.start_line)
    end

    def test_resolving_circular_alias
      index(<<~RUBY)
        module Namespace
          FOO = BAR
          BAR = FOO
        end
      RUBY

      foo_entry = T.must(@index.resolve("FOO", ["Namespace"])&.first)
      assert_equal(2, foo_entry.location.start_line)
      assert_instance_of(Entry::Alias, foo_entry)

      bar_entry = T.must(@index.resolve("BAR", ["Namespace"])&.first)
      assert_equal(3, bar_entry.location.start_line)
      assert_instance_of(Entry::Alias, bar_entry)
    end

    def test_resolving_circular_alias_three_levels
      index(<<~RUBY)
        module Namespace
          FOO = BAR
          BAR = BAZ
          BAZ = FOO
        end
      RUBY

      foo_entry = T.must(@index.resolve("FOO", ["Namespace"])&.first)
      assert_equal(2, foo_entry.location.start_line)
      assert_instance_of(Entry::Alias, foo_entry)

      bar_entry = T.must(@index.resolve("BAR", ["Namespace"])&.first)
      assert_equal(3, bar_entry.location.start_line)
      assert_instance_of(Entry::Alias, bar_entry)

      baz_entry = T.must(@index.resolve("BAZ", ["Namespace"])&.first)
      assert_equal(4, baz_entry.location.start_line)
      assert_instance_of(Entry::Alias, baz_entry)
    end

    def test_resolving_top_level_compact_reference
      index(<<~RUBY)
        class Foo::Bar
        end
      RUBY

      foo_entry = T.must(@index.resolve("Foo::Bar", [])&.first)
      assert_equal(1, foo_entry.location.start_line)
      assert_instance_of(Entry::Class, foo_entry)
    end

    def test_resolving_references_with_redundant_namespaces
      index(<<~RUBY)
        module Bar
          CONST = 1
        end

        module A
          CONST = 2

          module B
            CONST = 3

            class Foo
              include Bar
            end

            A::B::Foo::CONST
          end
        end
      RUBY

      foo_entry = T.must(@index.resolve("A::B::Foo::CONST", ["A", "B"])&.first)
      assert_equal(2, foo_entry.location.start_line)
    end

    def test_resolving_qualified_references
      index(<<~RUBY)
        module Namespace
          class Entry
            CONST = 1
          end
        end

        module Namespace
          class Index
          end
        end
      RUBY

      foo_entry = T.must(@index.resolve("Entry::CONST", ["Namespace", "Index"])&.first)
      assert_equal(3, foo_entry.location.start_line)
    end

    def test_resolving_unqualified_references
      index(<<~RUBY)
        module Foo
          CONST = 1
        end

        module Namespace
          CONST = 2

          class Index
            include Foo
          end
        end
      RUBY

      foo_entry = T.must(@index.resolve("CONST", ["Namespace", "Index"])&.first)
      assert_equal(6, foo_entry.location.start_line)
    end

    def test_resolving_references_with_only_top_level_declaration
      index(<<~RUBY)
        CONST = 1

        module Foo; end

        module Namespace
          class Index
            include Foo
          end
        end
      RUBY

      foo_entry = T.must(@index.resolve("CONST", ["Namespace", "Index"])&.first)
      assert_equal(1, foo_entry.location.start_line)
    end

    def test_instance_variables_completions_from_different_owners_with_conflicting_names
      index(<<~RUBY)
        class Foo
          def initialize
            @bar = 1
          end
        end

        class Bar
          def initialize
            @bar = 2
          end
        end
      RUBY

      entry = T.must(@index.instance_variable_completion_candidates("@", "Bar")&.first)
      assert_equal("@bar", entry.name)
      assert_equal("Bar", T.must(entry.owner).name)
    end

    def test_resolving_a_qualified_reference
      index(<<~RUBY)
        class Base
          module Third
            CONST = 1
          end
        end

        class Foo
          module Third
            CONST = 2
          end

          class Second < Base
          end
        end
      RUBY

      foo_entry = T.must(@index.resolve("Third::CONST", ["Foo"])&.first)
      assert_equal(9, foo_entry.location.start_line)
    end

    def test_resolving_unindexed_constant_with_no_nesting
      assert_nil(@index.resolve("RSpec", []))
    end

    def test_object_superclass_resolution
      @index.index_single(IndexablePath.new(nil, "/fake/path/foo.rb"), <<~RUBY)
        module Foo
          class Object; end

          class Bar; end
          class Baz < Object; end
        end
      RUBY

      assert_equal(["Foo::Bar", "Object", "Kernel", "BasicObject"], @index.linearized_ancestors_of("Foo::Bar"))
      assert_equal(
        ["Foo::Baz", "Foo::Object", "Object", "Kernel", "BasicObject"],
        @index.linearized_ancestors_of("Foo::Baz"),
      )
    end

    def test_top_level_object_superclass_resolution
      @index.index_single(IndexablePath.new(nil, "/fake/path/foo.rb"), <<~RUBY)
        module Foo
          class Object; end

          class Bar < ::Object; end
        end
      RUBY

      assert_equal(["Foo::Bar", "Object", "Kernel", "BasicObject"], @index.linearized_ancestors_of("Foo::Bar"))
    end
  end
end
