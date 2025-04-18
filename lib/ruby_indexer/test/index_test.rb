# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class IndexTest < TestCase
    def test_deleting_one_entry_for_a_class
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb"), <<~RUBY)
        class Foo
        end
      RUBY
      @index.index_single(URI::Generic.from_path(path: "/fake/path/other_foo.rb"), <<~RUBY)
        class Foo
        end
      RUBY

      entries = @index["Foo"] #: as !nil
      assert_equal(2, entries.length)

      @index.delete(URI::Generic.from_path(path: "/fake/path/other_foo.rb"))
      entries = @index["Foo"] #: as !nil
      assert_equal(1, entries.length)
    end

    def test_deleting_all_entries_for_a_class
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb"), <<~RUBY)
        class Foo
        end
      RUBY

      entries = @index["Foo"] #: as !nil
      assert_equal(1, entries.length)

      @index.delete(URI::Generic.from_path(path: "/fake/path/foo.rb"))
      entries = @index["Foo"]
      assert_nil(entries)
    end

    def test_index_resolve
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb"), <<~RUBY)
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

      entries = @index.resolve("Something", ["Foo", "Baz"]) #: as !nil
      refute_empty(entries)
      assert_equal("Foo::Baz::Something", entries.first&.name)

      entries = @index.resolve("Bar", ["Foo"]) #: as !nil
      refute_empty(entries)
      assert_equal("Foo::Bar", entries.first&.name)

      entries = @index.resolve("Bar", ["Foo", "Baz"]) #: as !nil
      refute_empty(entries)
      assert_equal("Foo::Bar", entries.first&.name)

      entries = @index.resolve("Foo::Bar", ["Foo", "Baz"]) #: as !nil
      refute_empty(entries)
      assert_equal("Foo::Bar", entries.first&.name)

      assert_nil(@index.resolve("DoesNotExist", ["Foo"]))
    end

    def test_accessing_with_colon_colon_prefix
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb"), <<~RUBY)
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

      entries = @index["::Foo::Baz::Something"] #: as !nil
      refute_empty(entries)
      assert_equal("Foo::Baz::Something", entries.first&.name)
    end

    def test_fuzzy_search
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb"), <<~RUBY)
        class Zws; end

        module Qtl
          class Zws
          end

          class Zwo
            class Something
            end
          end
        end
      RUBY

      result = @index.fuzzy_search("Zws")
      assert_equal(2, result.length)
      assert_equal(["Zws", "Qtl::Zwo::Something"], result.map(&:name))

      result = @index.fuzzy_search("qtlzwssomeking")
      assert_equal(5, result.length)
      assert_equal(["Qtl::Zwo::Something", "Qtl::Zws", "Qtl::Zwo", "Qtl", "Zws"], result.map(&:name))

      result = @index.fuzzy_search("QltZwo")
      assert_equal(4, result.length)
      assert_equal(["Qtl::Zwo", "Qtl::Zws", "Qtl::Zwo::Something", "Qtl"], result.map(&:name))
    end

    def test_index_single_ignores_directories
      path = "#{Dir.pwd}/lib/this_is_a_dir.rb"
      FileUtils.mkdir(path)

      begin
        @index.index_file(URI::Generic.from_path(path: path))
      ensure
        FileUtils.rm_r(path)
      end
    end

    def test_searching_for_require_paths
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb", load_path_entry: "/fake"), <<~RUBY)
        class Foo
        end
      RUBY
      @index.index_single(URI::Generic.from_path(path: "/fake/path/other_foo.rb", load_path_entry: "/fake"), <<~RUBY)
        class Foo
        end
      RUBY

      assert_equal(["path/other_foo", "path/foo"], @index.search_require_paths("path").map(&:require_path))
    end

    def test_searching_for_entries_based_on_prefix
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb", load_path_entry: "/fake"), <<~RUBY)
        class Foo::Bizw
        end
      RUBY
      @index.index_single(URI::Generic.from_path(path: "/fake/path/other_foo.rb", load_path_entry: "/fake"), <<~RUBY)
        class Foo::Bizw
        end

        class Foo::Bizt
        end
      RUBY

      results = @index.prefix_search("Foo", []).map { |entries| entries.map(&:name) }
      assert_equal([["Foo::Bizt"], ["Foo::Bizw", "Foo::Bizw"]], results)

      results = @index.prefix_search("Biz", ["Foo"]).map { |entries| entries.map(&:name) }
      assert_equal([["Foo::Bizt"], ["Foo::Bizw", "Foo::Bizw"]], results)
    end

    def test_resolve_normalizes_top_level_names
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb", load_path_entry: "/fake"), <<~RUBY)
        class Bar; end

        module Foo
          class Bar; end
        end
      RUBY

      entries = @index.resolve("::Foo::Bar", []) #: as !nil
      refute_nil(entries)

      assert_equal("Foo::Bar", entries.first&.name)

      entries = @index.resolve("::Bar", ["Foo"]) #: as !nil
      refute_nil(entries)

      assert_equal("Bar", entries.first&.name)
    end

    def test_resolving_aliases_to_non_existing_constants_with_conflicting_names
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb", load_path_entry: "/fake"), <<~RUBY)
        class Bar
        end

        module Foo
          class Bar < self
            BAZ = ::Bar::BAZ
          end
        end
      RUBY

      entry = @index.resolve("BAZ", ["Foo", "Bar"])&.first
      refute_nil(entry)

      assert_instance_of(Entry::UnresolvedConstantAlias, entry)
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

      entries = @index.resolve_method("baz", "Foo::Bar") #: as !nil
      assert_equal("baz", entries.first&.name)
      owner = entries.first&.owner #: as !nil
      assert_equal("Foo::Bar", owner.name)
    end

    def test_resolve_method_with_class_name_conflict
      index(<<~RUBY)
        class Array
        end

        class Foo
          def Array(*args); end
        end
      RUBY

      entries = @index.resolve_method("Array", "Foo") #: as !nil
      assert_equal("Array", entries.first&.name)
      owner = entries.first&.owner #: as !nil
      assert_equal("Foo", owner.name)
    end

    def test_resolve_method_attribute
      index(<<~RUBY)
        class Foo
          attr_reader :bar
        end
      RUBY

      entries = @index.resolve_method("bar", "Foo") #: as !nil
      assert_equal("bar", entries.first&.name)
      owner = entries.first&.owner #: as !nil
      assert_equal("Foo", owner.name)
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

      first_entry, second_entry = @index.resolve_method("bar", "Foo") #: as !nil

      assert_equal("bar", first_entry&.name)
      owner = first_entry&.owner #: as !nil
      assert_equal("Foo", owner.name)
      assert_includes(first_entry&.comments, "Hello from first `bar`")

      assert_equal("bar", second_entry&.name)
      owner = second_entry&.owner #: as !nil
      assert_equal("Foo", owner.name)
      assert_includes(second_entry&.comments, "Hello from second `bar`")
    end

    def test_resolve_method_inherited_only
      index(<<~RUBY)
        class Bar
          def baz; end
        end

        class Foo < Bar
          def baz; end
        end
      RUBY

      entry = @index.resolve_method("baz", "Foo", inherited_only: true)&.first #: as !nil
      assert_equal("Bar", entry.owner&.name)
    end

    def test_resolve_method_inherited_only_for_prepended_module
      index(<<~RUBY)
        module Bar
          def baz
            super
          end
        end

        class Foo
          prepend Bar

          def baz; end
        end
      RUBY

      # This test is just to document the fact that we don't yet support resolving inherited methods for modules that
      # are prepended. The only way to support this is to find all namespaces that have the module a subtype, so that we
      # can show the results for everywhere the module has been prepended.
      assert_nil(@index.resolve_method("baz", "Bar", inherited_only: true))
    end

    def test_prefix_search_for_methods
      index(<<~RUBY)
        module Foo
          module Bar
            def qzx; end
          end
        end
      RUBY

      entries = @index.prefix_search("qz")
      refute_empty(entries)

      entry = entries.first&.first #: as !nil
      assert_equal("qzx", entry.name)
    end

    def test_indexing_prism_fixtures_succeeds
      unless Dir.exist?("test/fixtures/prism/test/prism/fixtures")
        raise "Prism fixtures not found. Run `git submodule update --init` to fetch them."
      end

      fixtures = Dir.glob("#{Dir.pwd}/test/fixtures/prism/test/prism/fixtures/**/*.txt")

      fixtures.each do |fixture|
        uri = URI::Generic.from_path(path: fixture)
        @index.index_file(uri)
      end

      refute_empty(@index)
    end

    def test_index_single_does_not_fail_for_non_existing_file
      @index.index_file(URI::Generic.from_path(path: "/fake/path/foo.rb"))
      entries_after_indexing = @index.names
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

      entry = @index.resolve_method("baz", "Wow")&.first #: as !nil
      assert_equal("baz", entry.name)
      assert_equal("Foo", entry.owner&.name)

      entry = @index.resolve_method("qux", "Wow")&.first #: as !nil
      assert_equal("qux", entry.name)
      assert_equal("Bar", entry.owner&.name)
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

      entries = @index.resolve_method("qux", "Wow") #: as !nil
      assert_equal(1, entries.length)

      entry = entries.first #: as !nil
      assert_equal("qux", entry.name)
      assert_equal("Foo", entry.owner&.name)
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

          uri = URI::Generic.from_path(path: File.join(dir, "foo.rb"))
          @index.index_file(uri)

          assert_equal(["Bar", "Foo", "Object", "Kernel", "BasicObject"], @index.linearized_ancestors_of("Bar"))

          # Remove include to invalidate the ancestor tree
          File.write(File.join(dir, "foo.rb"), <<~RUBY)
            module Foo
            end

            class Bar
            end
          RUBY

          path = uri.full_path #: as !nil
          @index.handle_change(uri, File.read(path))
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

          uri = URI::Generic.from_path(path: File.join(dir, "foo.rb"))
          @index.index_file(uri)

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

          path = uri.full_path #: as !nil
          @index.handle_change(uri, File.read(path))
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

          uri = URI::Generic.from_path(path: File.join(dir, "foo.rb"))
          @index.index_file(uri)

          assert_equal(["Bar", "Foo", "Object", "Kernel", "BasicObject"], @index.linearized_ancestors_of("Bar"))

          # Remove include to invalidate the ancestor tree
          File.write(File.join(dir, "foo.rb"), <<~RUBY)
            class Foo
            end

            class Bar
            end
          RUBY

          path = uri.full_path #: as !nil
          @index.handle_change(uri, File.read(path))
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

      entry = @index.resolve("CONST", ["Namespace", "Bar"])&.first #: as !nil
      assert_equal(14, entry.location.start_line)
    end

    def test_resolving_inherited_aliased_namespace
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

      entry = @index.resolve("Foo::CONST::TARGET", [])&.first #: as !nil
      assert_equal(2, entry.location.start_line)

      entry = @index.resolve("Namespace::Bar::CONST::TARGET", [])&.first #: as !nil
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

      entry = @index.resolve("CONST", ["Namespace", "Child"])&.first #: as !nil
      assert_equal(2, entry.location.start_line)

      entry = @index.resolve("Namespace::Child::CONST", [])&.first #: as !nil
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

      entry = @index.resolve("CONST", ["Foo"])&.first #: as !nil
      assert_equal(6, entry.location.start_line)

      entry = @index.resolve("Foo::CONST", [])&.first #: as !nil
      assert_equal(6, entry.location.start_line)

      entry = @index.resolve("Bar::CONST", [])&.first #: as !nil
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

      entry = @index.resolve("CONST", ["First", "Second"])&.first #: as !nil
      assert_equal(6, entry.location.start_line)
    end

    def test_resolving_circular_alias
      index(<<~RUBY)
        module Namespace
          FOO = BAR
          BAR = FOO
        end
      RUBY

      foo_entry = @index.resolve("FOO", ["Namespace"])&.first #: as !nil
      assert_equal(2, foo_entry.location.start_line)
      assert_instance_of(Entry::ConstantAlias, foo_entry)

      bar_entry = @index.resolve("BAR", ["Namespace"])&.first #: as !nil
      assert_equal(3, bar_entry.location.start_line)
      assert_instance_of(Entry::ConstantAlias, bar_entry)
    end

    def test_resolving_circular_alias_three_levels
      index(<<~RUBY)
        module Namespace
          FOO = BAR
          BAR = BAZ
          BAZ = FOO
        end
      RUBY

      foo_entry = @index.resolve("FOO", ["Namespace"])&.first #: as !nil
      assert_equal(2, foo_entry.location.start_line)
      assert_instance_of(Entry::ConstantAlias, foo_entry)

      bar_entry = @index.resolve("BAR", ["Namespace"])&.first #: as !nil
      assert_equal(3, bar_entry.location.start_line)
      assert_instance_of(Entry::ConstantAlias, bar_entry)

      baz_entry = @index.resolve("BAZ", ["Namespace"])&.first #: as !nil
      assert_equal(4, baz_entry.location.start_line)
      assert_instance_of(Entry::ConstantAlias, baz_entry)
    end

    def test_resolving_constants_in_aliased_namespace
      index(<<~RUBY)
        module Original
          module Something
            CONST = 123
          end
        end

        module Other
          ALIAS = Original::Something
        end

        module Third
          Other::ALIAS::CONST
        end
      RUBY

      entry = @index.resolve("Other::ALIAS::CONST", ["Third"])&.first #: as !nil
      assert_kind_of(Entry::Constant, entry)
      assert_equal("Original::Something::CONST", entry.name)
    end

    def test_resolving_top_level_aliases
      index(<<~RUBY)
        class Foo
          CONST = 123
        end

        FOO = Foo
        FOO::CONST
      RUBY

      entry = @index.resolve("FOO::CONST", [])&.first #: as !nil
      assert_kind_of(Entry::Constant, entry)
      assert_equal("Foo::CONST", entry.name)
    end

    def test_resolving_top_level_compact_reference
      index(<<~RUBY)
        class Foo::Bar
        end
      RUBY

      foo_entry = @index.resolve("Foo::Bar", [])&.first #: as !nil
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

      foo_entry = @index.resolve("A::B::Foo::CONST", ["A", "B"])&.first #: as !nil
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

      foo_entry = @index.resolve("Entry::CONST", ["Namespace", "Index"])&.first #: as !nil
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

      foo_entry = @index.resolve("CONST", ["Namespace", "Index"])&.first #: as !nil
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

      foo_entry = @index.resolve("CONST", ["Namespace", "Index"])&.first #: as !nil
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

      entry = @index.instance_variable_completion_candidates("@", "Bar").first #: as !nil
      assert_equal("@bar", entry.name)
      assert_equal("Bar", entry.owner&.name)
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

      foo_entry = @index.resolve("Third::CONST", ["Foo"])&.first #: as !nil
      assert_equal(9, foo_entry.location.start_line)
    end

    def test_resolving_unindexed_constant_with_no_nesting
      assert_nil(@index.resolve("RSpec", []))
    end

    def test_object_superclass_indexing_and_resolution_with_reopened_object_class
      index(<<~RUBY)
        class Object; end
      RUBY

      entries = @index["Object"] #: as !nil
      assert_equal(2, entries.length)
      reopened_entry = entries.last #: as Entry::Class
      assert_equal("::BasicObject", reopened_entry.parent_class)
      assert_equal(["Object", "Kernel", "BasicObject"], @index.linearized_ancestors_of("Object"))
    end

    def test_object_superclass_indexing_and_resolution_with_reopened_basic_object_class
      index(<<~RUBY)
        class BasicObject; end
      RUBY

      entries = @index["BasicObject"] #: as !nil
      assert_equal(2, entries.length)
      reopened_entry = entries.last #: as Entry::Class
      assert_nil(reopened_entry.parent_class)
      assert_equal(["BasicObject"], @index.linearized_ancestors_of("BasicObject"))
    end

    def test_object_superclass_resolution
      index(<<~RUBY)
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

    def test_basic_object_superclass_resolution
      index(<<~RUBY)
        module Foo
          class BasicObject; end

          class Bar; end
          class Baz < BasicObject; end
        end
      RUBY

      assert_equal(["Foo::Bar", "Object", "Kernel", "BasicObject"], @index.linearized_ancestors_of("Foo::Bar"))
      assert_equal(
        ["Foo::Baz", "Foo::BasicObject", "Object", "Kernel", "BasicObject"],
        @index.linearized_ancestors_of("Foo::Baz"),
      )
    end

    def test_top_level_object_superclass_resolution
      index(<<~RUBY)
        module Foo
          class Object; end

          class Bar < ::Object; end
        end
      RUBY

      assert_equal(["Foo::Bar", "Object", "Kernel", "BasicObject"], @index.linearized_ancestors_of("Foo::Bar"))
    end

    def test_top_level_basic_object_superclass_resolution
      index(<<~RUBY)
        module Foo
          class BasicObject; end

          class Bar < ::BasicObject; end
        end
      RUBY

      assert_equal(["Foo::Bar", "BasicObject"], @index.linearized_ancestors_of("Foo::Bar"))
    end

    def test_resolving_method_inside_singleton_context
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb"), <<~RUBY)
        module Foo
          class Bar
            class << self
              class Baz
                class << self
                  def found_me!; end
                end
              end
            end
          end
        end
      RUBY

      entry = @index.resolve_method("found_me!", "Foo::Bar::<Class:Bar>::Baz::<Class:Baz>")&.first #: as !nil
      refute_nil(entry)
      assert_equal("found_me!", entry.name)
    end

    def test_resolving_constants_in_singleton_contexts
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb"), <<~RUBY)
        module Foo
          class Bar
            CONST = 3

            class << self
              CONST = 2

              class Baz
                CONST = 1

                class << self
                end
              end
            end
          end
        end
      RUBY

      entry = @index.resolve("CONST", ["Foo", "Bar", "<Class:Bar>", "Baz", "<Class:Baz>"])&.first #: as !nil
      refute_nil(entry)
      assert_equal(9, entry.location.start_line)
    end

    def test_resolving_instance_variables_in_singleton_contexts
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb"), <<~RUBY)
        module Foo
          class Bar
            @a = 123

            class << self
              def hello
                @b = 123
              end

              @c = 123
            end
          end
        end
      RUBY

      entry = @index.resolve_instance_variable("@a", "Foo::Bar::<Class:Bar>")&.first #: as !nil
      refute_nil(entry)
      assert_equal("@a", entry.name)

      entry = @index.resolve_instance_variable("@b", "Foo::Bar::<Class:Bar>")&.first #: as !nil
      refute_nil(entry)
      assert_equal("@b", entry.name)

      entry = @index.resolve_instance_variable("@c", "Foo::Bar::<Class:Bar>::<Class:<Class:Bar>>")&.first #: as !nil
      refute_nil(entry)
      assert_equal("@c", entry.name)
    end

    def test_instance_variable_completion_in_singleton_contexts
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb"), <<~RUBY)
        module Foo
          class Bar
            @a = 123

            class << self
              def hello
                @b = 123
              end

              @c = 123
            end
          end
        end
      RUBY

      entries = @index.instance_variable_completion_candidates("@", "Foo::Bar::<Class:Bar>").map(&:name)
      assert_includes(entries, "@a")
      assert_includes(entries, "@b")
    end

    def test_singletons_are_excluded_from_prefix_search
      index(<<~RUBY)
        class Zwq
          class << self
          end
        end
      RUBY

      assert_empty(@index.prefix_search("Zwq::<C"))
    end

    def test_singletons_are_excluded_from_fuzzy_search
      index(<<~RUBY)
        class Zwq
          class << self
          end
        end
      RUBY

      results = @index.fuzzy_search("Zwq")
      assert_equal(1, results.length)
      assert_equal("Zwq", results.first&.name)
    end

    def test_resolving_method_aliases
      index(<<~RUBY)
        class Foo
          def bar(a, b, c)
          end

          alias double_alias bar
        end

        class Bar < Foo
          def hello(b); end

          alias baz bar
          alias_method :qux, :hello
          alias double double_alias
        end
      RUBY

      # baz
      methods = @index.resolve_method("baz", "Bar") #: as !nil
      refute_nil(methods)

      entry = methods.first #: as Entry::MethodAlias
      assert_kind_of(Entry::MethodAlias, entry)
      assert_equal("bar", entry.target.name)
      assert_equal("Foo", entry.target.owner&.name)

      # qux
      methods = @index.resolve_method("qux", "Bar") #: as !nil
      refute_nil(methods)

      entry = methods.first #: as Entry::MethodAlias
      assert_kind_of(Entry::MethodAlias, entry)
      assert_equal("hello", entry.target.name)
      assert_equal("Bar", entry.target.owner&.name)

      # double
      methods = @index.resolve_method("double", "Bar") #: as !nil
      refute_nil(methods)

      entry = methods.first #: as Entry::MethodAlias
      assert_kind_of(Entry::MethodAlias, entry)

      target = entry.target #: as Entry::MethodAlias
      assert_equal("double_alias", target.name)
      assert_kind_of(Entry::MethodAlias, target)
      assert_equal("Foo", target.owner&.name)

      final_target = target.target
      assert_equal("bar", final_target.name)
      assert_kind_of(Entry::Method, final_target)
      assert_equal("Foo", final_target.owner&.name)
    end

    def test_resolving_circular_method_aliases
      index(<<~RUBY)
        class Foo
          alias bar bar
        end
      RUBY

      # It's not possible to resolve an alias that points to itself
      methods = @index.resolve_method("bar", "Foo")
      assert_nil(methods)

      entry = @index["bar"]&.first
      assert_kind_of(Entry::UnresolvedMethodAlias, entry)
    end

    def test_unresolvable_method_aliases
      index(<<~RUBY)
        class Foo
          alias bar baz
        end
      RUBY

      # `baz` does not exist, so resolving `bar` is not possible
      methods = @index.resolve_method("bar", "Foo")
      assert_nil(methods)

      entry = @index["bar"]&.first
      assert_kind_of(Entry::UnresolvedMethodAlias, entry)
    end

    def test_only_aliases_for_the_right_owner_are_resolved
      index(<<~RUBY)
        class Foo
          attr_reader :name
          alias_method :decorated_name, :name
        end

        class Bar
          alias_method :decorated_name, :to_s
        end
      RUBY

      methods = @index.resolve_method("decorated_name", "Foo") #: as !nil
      refute_nil(methods)

      entry = methods.first #: as Entry::MethodAlias
      assert_kind_of(Entry::MethodAlias, entry)

      target = entry.target
      assert_equal("name", target.name)
      assert_kind_of(Entry::Accessor, target)
      assert_equal("Foo", target.owner&.name)

      other_decorated_name = @index["decorated_name"]&.find { |e| e.is_a?(Entry::UnresolvedMethodAlias) }
      assert_kind_of(Entry::UnresolvedMethodAlias, other_decorated_name)
    end

    def test_completion_does_not_include_unresolved_aliases
      index(<<~RUBY)
        class Foo
          alias_method :bar, :missing
        end
      RUBY

      assert_empty(@index.method_completion_candidates("bar", "Foo"))
    end

    def test_first_unqualified_const
      index(<<~RUBY)
        module Foo
          class Bar; end
        end

        module Baz
          class Bar; end
        end
      RUBY

      entry = @index.first_unqualified_const("Bar")&.first #: as !nil
      assert_equal("Foo::Bar", entry.name)
    end

    def test_first_unqualified_const_prefers_exact_matches
      index(<<~RUBY)
        module Foo
          class ParseResultType
          end
        end

        module Namespace
          class Type
          end
        end
      RUBY

      entry = @index.first_unqualified_const("Type")&.first #: as !nil
      assert_equal("Namespace::Type", entry.name)
    end

    def test_completion_does_not_duplicate_overridden_methods
      index(<<~RUBY)
        class Foo
          def bar; end
        end

        class Baz < Foo
          def bar; end
        end
      RUBY

      entries = @index.method_completion_candidates("bar", "Baz")
      assert_equal(["bar"], entries.map(&:name))
      assert_equal("Baz", entries.first&.owner&.name)
    end

    def test_completion_does_not_duplicate_methods_overridden_by_aliases
      index(<<~RUBY)
        class Foo
          def bar; end
        end

        class Baz < Foo
          alias bar to_s
        end
      RUBY

      entries = @index.method_completion_candidates("bar", "Baz")
      assert_equal(["bar"], entries.map(&:name))
      assert_equal("Baz", entries.first&.owner&.name)
    end

    def test_decorated_parameters
      index(<<~RUBY)
        class Foo
          def bar(a, b = 1, c: 2)
          end
        end
      RUBY

      methods = @index.resolve_method("bar", "Foo") #: as !nil
      refute_nil(methods)

      entry = methods.first #: as Entry::Method
      assert_equal("(a, b = <default>, c: <default>)", entry.decorated_parameters)
    end

    def test_decorated_parameters_when_method_has_no_parameters
      index(<<~RUBY)
        class Foo
          def bar
          end
        end
      RUBY

      methods = @index.resolve_method("bar", "Foo") #: as !nil
      refute_nil(methods)

      entry = methods.first #: as Entry::Method
      assert_equal("()", entry.decorated_parameters)
    end

    def test_linearizing_singleton_ancestors_of_singleton_when_class_has_parent
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb"), <<~RUBY)
        class Foo; end

        class Bar < Foo
        end

        class Baz < Bar
          class << self
            class << self
            end
          end
        end
      RUBY

      assert_equal(
        [
          "Baz::<Class:Baz>::<Class:<Class:Baz>>",
          "Bar::<Class:Bar>::<Class:<Class:Bar>>",
          "Foo::<Class:Foo>::<Class:<Class:Foo>>",
          "Object::<Class:Object>::<Class:<Class:Object>>",
          "BasicObject::<Class:BasicObject>::<Class:<Class:BasicObject>>",
          "Class::<Class:Class>",
          "Module::<Class:Module>",
          "Object::<Class:Object>",
          "BasicObject::<Class:BasicObject>",
          "Class",
          "Module",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Baz::<Class:Baz>::<Class:<Class:Baz>>"),
      )
    end

    def test_linearizing_singleton_object
      assert_equal(
        [
          "Object::<Class:Object>",
          "BasicObject::<Class:BasicObject>",
          "Class",
          "Module",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Object::<Class:Object>"),
      )
    end

    def test_extend_self
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb"), <<~RUBY)
        module Foo
          def bar
          end

          extend self

          def baz
          end
        end
      RUBY

      ["bar", "baz"].product(["Foo", "Foo::<Class:Foo>"]).each do |method, receiver|
        entry = @index.resolve_method(method, receiver)&.first #: as !nil
        refute_nil(entry)
        assert_equal(method, entry.name)
      end

      assert_equal(
        [
          "Foo::<Class:Foo>",
          "Foo",
          "Module",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Foo::<Class:Foo>"),
      )
    end

    def test_linearizing_singleton_ancestors
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb"), <<~RUBY)
        module First
        end

        module Second
          include First
        end

        module Foo
          class Bar
            class << self
              class Baz
                extend Second

                class << self
                  include First
                end
              end
            end
          end
        end
      RUBY

      assert_equal(
        [
          "Foo::Bar::<Class:Bar>::Baz::<Class:Baz>",
          "Second",
          "First",
          "Object::<Class:Object>",
          "BasicObject::<Class:BasicObject>",
          "Class",
          "Module",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Foo::Bar::<Class:Bar>::Baz::<Class:Baz>"),
      )
    end

    def test_linearizing_singleton_ancestors_when_class_has_parent
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb"), <<~RUBY)
        class Foo; end

        class Bar < Foo
        end

        class Baz < Bar
          class << self
          end
        end
      RUBY

      assert_equal(
        [
          "Baz::<Class:Baz>",
          "Bar::<Class:Bar>",
          "Foo::<Class:Foo>",
          "Object::<Class:Object>",
          "BasicObject::<Class:BasicObject>",
          "Class",
          "Module",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Baz::<Class:Baz>"),
      )
    end

    def test_linearizing_a_module_singleton_class
      @index.index_single(URI::Generic.from_path(path: "/fake/path/foo.rb"), <<~RUBY)
        module A; end
      RUBY

      assert_equal(
        [
          "A::<Class:A>",
          "Module",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("A::<Class:A>"),
      )
    end

    def test_linearizing_a_singleton_class_with_no_attached
      assert_raises(Index::NonExistingNamespaceError) do
        @index.linearized_ancestors_of("A::<Class:A>")
      end
    end

    def test_linearizing_singleton_parent_class_with_namespace
      index(<<~RUBY)
        class ActiveRecord::Base; end

        class User < ActiveRecord::Base
        end
      RUBY

      assert_equal(
        [
          "User::<Class:User>",
          "ActiveRecord::Base::<Class:Base>",
          "Object::<Class:Object>",
          "BasicObject::<Class:BasicObject>",
          "Class",
          "Module",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("User::<Class:User>"),
      )
    end

    def test_singleton_nesting_is_correctly_split_during_linearization
      index(<<~RUBY)
        module Bar; end

        module Foo
          class Namespace::Parent
            extend Bar
          end
        end

        module Foo
          class Child < Namespace::Parent
          end
        end
      RUBY

      assert_equal(
        [
          "Foo::Child::<Class:Child>",
          "Foo::Namespace::Parent::<Class:Parent>",
          "Bar",
          "Object::<Class:Object>",
          "BasicObject::<Class:BasicObject>",
          "Class",
          "Module",
          "Object",
          "Kernel",
          "BasicObject",
        ],
        @index.linearized_ancestors_of("Foo::Child::<Class:Child>"),
      )
    end

    def test_resolving_circular_method_aliases_on_class_reopen
      index(<<~RUBY)
        class Foo
          alias bar ==
          def ==(other) = true
        end

        class Foo
          alias == bar
        end
      RUBY

      method = @index.resolve_method("==", "Foo")&.first #: as Entry::Method
      assert_kind_of(Entry::Method, method)
      assert_equal("==", method.name)

      candidates = @index.method_completion_candidates("=", "Foo")
      assert_equal(["==", "==="], candidates.map(&:name))
    end

    def test_entries_for
      index(<<~RUBY)
        class Foo; end

        module Bar
          def my_def; end
          def self.my_singleton_def; end
        end
      RUBY

      entries = @index.entries_for("file:///fake/path/foo.rb", Entry) #: as !nil
      assert_equal(["Foo", "Bar", "my_def", "Bar::<Class:Bar>", "my_singleton_def"], entries.map(&:name))

      entries = @index.entries_for("file:///fake/path/foo.rb", RubyIndexer::Entry::Namespace) #: as !nil
      assert_equal(["Foo", "Bar", "Bar::<Class:Bar>"], entries.map(&:name))

      entries = @index.entries_for("file:///fake/path/foo.rb") #: as !nil
      assert_equal(["Foo", "Bar", "my_def", "Bar::<Class:Bar>", "my_singleton_def"], entries.map(&:name))
    end

    def test_entries_for_returns_nil_if_no_matches
      assert_nil(@index.entries_for("non_existing_file.rb", Entry::Namespace))
    end

    def test_constant_completion_candidates_all_possible_constants
      index(<<~RUBY)
        XQRK = 3

        module Bar
          XQRK = 2
        end

        module Foo
          XQRK = 1
        end

        module Namespace
          XQRK = 0

          class Baz
            include Foo
            include Bar
          end
        end
      RUBY

      result = @index.constant_completion_candidates("X", ["Namespace", "Baz"])

      result.each do |entries|
        name = entries.first&.name
        assert(entries.all? { |e| e.name == name })
      end

      assert_equal(["Namespace::XQRK", "Bar::XQRK", "XQRK"], result.map { |entries| entries.first&.name })

      result = @index.constant_completion_candidates("::X", ["Namespace", "Baz"])
      assert_equal(["XQRK"], result.map { |entries| entries.first&.name })
    end

    def test_constant_completion_candidates_for_empty_name
      index(<<~RUBY)
        module Foo
          Bar = 1
        end

        class Baz
          include Foo
        end
      RUBY

      result = @index.constant_completion_candidates("Baz::", [])
      assert_includes(result.map { |entries| entries.first&.name }, "Foo::Bar")
    end

    def test_follow_alias_namespace
      index(<<~RUBY)
        module First
          module Second
            class Foo
            end
          end
        end

        module Namespace
          Second = First::Second
        end
      RUBY

      real_namespace = @index.follow_aliased_namespace("Namespace::Second")
      assert_equal("First::Second", real_namespace)
    end

    def test_resolving_alias_to_non_existing_namespace
      index(<<~RUBY)
        module Namespace
          class Foo
            module InnerNamespace
              Constants = Namespace::Foo::Constants
            end
          end
        end
      RUBY

      entry = @index.resolve("Constants", ["Namespace", "Foo", "InnerNamespace"])&.first
      assert_instance_of(Entry::UnresolvedConstantAlias, entry)

      entry = @index.resolve("Namespace::Foo::Constants", ["Namespace", "Foo", "InnerNamespace"])&.first
      assert_nil(entry)
    end

    def test_resolving_alias_to_existing_constant_from_inner_namespace
      index(<<~RUBY)
        module Parent
          CONST = 123
        end

        module First
          module Namespace
            class Foo
              include Parent

              module InnerNamespace
                Constants = Namespace::Foo::CONST
              end
            end
          end
        end
      RUBY

      entry = @index.resolve("Namespace::Foo::CONST", ["First", "Namespace", "Foo", "InnerNamespace"])&.first #: as !nil
      assert_equal("Parent::CONST", entry.name)
      assert_instance_of(Entry::Constant, entry)
    end

    def test_build_non_redundant_name
      assert_equal(
        "Namespace::Foo::Constants",
        @index.send(
          :build_non_redundant_full_name,
          "Namespace::Foo::Constants",
          ["Namespace", "Foo", "InnerNamespace"],
        ),
      )

      assert_equal(
        "Namespace::Foo::Constants",
        @index.send(
          :build_non_redundant_full_name,
          "Namespace::Foo::Constants",
          ["Namespace", "Foo"],
        ),
      )

      assert_equal(
        "Namespace::Foo::Constants",
        @index.send(
          :build_non_redundant_full_name,
          "Foo::Constants",
          ["Namespace", "Foo"],
        ),
      )

      assert_equal(
        "Bar::Namespace::Foo::Constants",
        @index.send(
          :build_non_redundant_full_name,
          "Namespace::Foo::Constants",
          ["Bar"],
        ),
      )

      assert_equal(
        "First::Namespace::Foo::Constants",
        @index.send(
          :build_non_redundant_full_name,
          "Namespace::Foo::Constants",
          ["First", "Namespace", "Foo", "InnerNamespace"],
        ),
      )
    end

    def test_prevents_multiple_calls_to_index_all
      @index.index_all

      assert_raises(Index::IndexNotEmptyError) do
        @index.index_all
      end
    end

    def test_index_can_handle_entries_from_untitled_scheme
      uri = URI("untitled:Untitled-1")

      index(<<~RUBY, uri: uri)
        class Foo
        end
      RUBY

      entry = @index["Foo"]&.first #: as !nil
      refute_nil(entry, "Expected indexer to be able to handle unsaved URIs")
      assert_equal("untitled:Untitled-1", entry.uri.to_s)
      assert_equal("Untitled-1", entry.file_name)
      assert_nil(entry.file_path)

      @index.handle_change(uri, <<~RUBY)
        # I added this comment!
        class Foo
        end
      RUBY

      entry = @index["Foo"]&.first #: as !nil
      refute_nil(entry, "Expected indexer to be able to handle unsaved URIs")
      assert_equal("I added this comment!", entry.comments)
    end

    def test_instance_variable_completion_returns_class_variables_too
      index(<<~RUBY)
        class Parent
          @@abc = 123
        end

        class Child < Parent
          @@adf = 123

          def self.do
          end
        end
      RUBY

      adf, abc = @index.instance_variable_completion_candidates("@", "Child::<Class:Child>")

      refute_nil(abc)
      refute_nil(adf)

      assert_equal("@@abc", abc&.name)
      assert_equal("@@adf", adf&.name)
    end

    def test_class_variable_completion_from_singleton_context
      index(<<~RUBY)
        class Foo
          @@hello = 123

          def self.do
          end
        end
      RUBY

      candidates = @index.class_variable_completion_candidates("@@", "Foo::<Class:Foo>")
      refute_empty(candidates)

      assert_equal("@@hello", candidates.first&.name)
    end

    def test_resolve_class_variable_in_singleton_context
      index(<<~RUBY)
        class Foo
          @@hello = 123
        end
      RUBY

      candidates = @index.resolve_class_variable("@@hello", "Foo::<Class:Foo>") #: as !nil
      refute_empty(candidates)

      assert_equal("@@hello", candidates.first&.name)
    end

    def test_actual_nesting
      assert_equal(["Foo"], Index.actual_nesting([], "Foo"))
      assert_equal(["TopLevel", "Foo"], Index.actual_nesting(["First", "::TopLevel"], "Foo"))
      assert_equal(["TopLevel", "Another", "Foo"], Index.actual_nesting(["::TopLevel", "Another"], "Foo"))
      assert_equal(["TopLevel"], Index.actual_nesting(["First", "::TopLevel"], nil))
    end

    def test_constant_name
      node = Prism.parse("class var::Foo; end").value.statements.body.first.constant_path
      assert_nil(Index.constant_name(node))

      node = Prism.parse("class ; end").value.statements.body.first.constant_path
      assert_nil(Index.constant_name(node))

      node = Prism.parse("class method_call; end").value.statements.body.first.constant_path
      assert_nil(Index.constant_name(node))

      node = Prism.parse("class Foo; end").value.statements.body.first.constant_path
      assert_equal("Foo", Index.constant_name(node))
    end
  end
end
