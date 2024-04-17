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

      entry = @index.get_constant("Foo")
      declarations = entry.declarations
      assert_equal(2, declarations.length)

      @index.delete(IndexablePath.new(nil, "/fake/path/other_foo.rb"))
      assert_equal(1, declarations.length)
    end

    def test_deleting_all_entries_for_a_class
      @index.index_single(IndexablePath.new(nil, "/fake/path/foo.rb"), <<~RUBY)
        class Foo
        end
      RUBY

      entry = @index.get_constant("Foo")
      declarations = entry.declarations
      assert_equal(1, declarations.length)

      @index.delete(IndexablePath.new(nil, "/fake/path/foo.rb"))
      assert_nil(@index.get_constant("Foo"))
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

      entry = T.must(@index.resolve_constant("Something", ["Foo", "Baz"]))
      assert_equal("Foo::Baz::Something", entry.name)

      entry = T.must(@index.resolve_constant("Bar", ["Foo"]))
      assert_equal("Foo::Bar", entry.name)

      entry = T.must(@index.resolve_constant("Bar", ["Foo", "Baz"]))
      assert_equal("Foo::Bar", entry.name)

      entry = T.must(@index.resolve_constant("Foo::Bar", ["Foo", "Baz"]))
      assert_equal("Foo::Bar", entry.name)

      assert_nil(@index.resolve_constant("DoesNotExist", ["Foo"]))
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

      entry = @index.get_constant("::Foo::Baz::Something")
      refute_nil(entry)
      assert_equal("Foo::Baz::Something", T.must(entry).name)
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
      assert_equal(1, result.length)
      assert_equal(@index.get_constant("Bar"), result.first)

      result = @index.fuzzy_search("foobarsomeking")
      assert_equal(5, result.length)
      assert_equal(["Foo::Baz::Something", "Foo::Bar", "Foo::Baz", "Foo", "Bar"], result.map(&:name))

      result = @index.fuzzy_search("FooBaz")
      assert_equal(4, result.length)
      assert_equal(["Foo::Baz", "Foo::Bar", "Foo", "Foo::Baz::Something"], result.map(&:name))
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

      results = @index.prefix_search_constants("Foo", []).map(&:name)
      assert_equal(["Foo::Bar", "Foo::Baz"], results)

      results = @index.prefix_search_constants("Ba", ["Foo"]).map(&:name)
      assert_equal(["Foo::Bar", "Foo::Baz"], results)
    end

    def test_resolve_normalizes_top_level_names
      @index.index_single(IndexablePath.new("/fake", "/fake/path/foo.rb"), <<~RUBY)
        class Bar; end

        module Foo
          class Bar; end
        end
      RUBY

      entry = T.must(@index.resolve_constant("::Foo::Bar", []))
      assert_equal("Foo::Bar", entry.name)

      entry = T.must(@index.resolve_constant("::Bar", ["Foo"]))
      assert_equal("Bar", entry.name)
    end

    def test_resolving_aliases_to_non_existing_constants_with_conflicting_names
      @index.index_single(IndexablePath.new("/fake", "/fake/path/foo.rb"), <<~RUBY)
        module Foo
          class Float < self
            INFINITY = ::Float::INFINITY
          end
        end
      RUBY

      entry = @index.resolve_constant("INFINITY", ["Foo", "Float"])
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

      entry = T.must(@index.resolve_method("baz", "Foo::Bar"))
      assert_equal("baz", entry.name)
      assert_equal("Foo::Bar", T.must(entry.owner).name)
    end

    def test_resolve_method_with_class_name_conflict
      index(<<~RUBY)
        class Array
        end

        class Foo
          def Array(*args); end
        end
      RUBY

      entry = T.must(@index.resolve_method("Array", "Foo"))
      assert_equal("Array", entry.name)
      assert_equal("Foo", T.must(entry.owner).name)
    end

    def test_resolve_method_attribute
      index(<<~RUBY)
        class Foo
          attr_reader :bar
        end
      RUBY

      entry = T.must(@index.resolve_method("bar", "Foo"))
      assert_equal("bar", entry.name)
      assert_equal("Foo", T.must(entry.owner).name)
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

      entry = T.must(@index.resolve_method("bar", "Foo"))
      first_declaration, second_declaration = entry.declarations

      assert_equal("Foo", T.must(entry.owner).name)
      assert_includes(first_declaration.comments, "Hello from first `bar`")
      assert_includes(second_declaration.comments, "Hello from second `bar`")
    end

    def test_prefix_search_for_methods
      index(<<~RUBY)
        module Foo
          module Bar
            def baz; end
          end
        end
      RUBY

      entries = @index.prefix_search_methods("ba")
      refute_empty(entries)

      entry = T.must(T.must(entries.first).first)
      assert_equal("baz", entry.name)
    end

    def test_indexing_prism_fixtures_succeeds
      fixtures = Dir.glob("test/fixtures/prism/test/prism/fixtures/**/*.txt")

      fixtures.each do |fixture|
        indexable_path = IndexablePath.new("", fixture)
        @index.index_single(indexable_path)
      end

      refute_empty(@index.instance_variable_get(:@constant_entries))
      refute_empty(@index.instance_variable_get(:@method_entries))
    end

    def test_index_single_does_not_fail_for_non_existing_file
      @index.index_single(IndexablePath.new(nil, "/fake/path/foo.rb"))
      assert_empty(@index.instance_variable_get(:@constant_entries))
      assert_empty(@index.instance_variable_get(:@method_entries))
    end
  end
end
