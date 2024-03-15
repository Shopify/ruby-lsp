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
      assert_equal(1, result.length)
      assert_equal(@index["Bar"].first, result.first)

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
      fixtures = Dir.glob("test/fixtures/prism/test/prism/fixtures/**/*.txt")

      fixtures.each do |fixture|
        indexable_path = IndexablePath.new("", fixture)
        @index.index_single(indexable_path)
      end

      refute_empty(@index.instance_variable_get(:@entries))
    end

    def test_index_single_does_not_fail_for_non_existing_file
      @index.index_single(IndexablePath.new(nil, "/fake/path/foo.rb"))
      assert_empty(@index.instance_variable_get(:@entries))
    end
  end
end
