# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class IndexTest < TestCase
    def test_deleting_one_entry_for_a_class
      @index.index_single("/fake/path/foo.rb", <<~RUBY)
        class Foo
        end
      RUBY
      @index.index_single("/fake/path/other_foo.rb", <<~RUBY)
        class Foo
        end
      RUBY

      entries = @index["Foo"]
      assert_equal(2, entries.length)

      @index.delete("/fake/path/other_foo.rb")
      entries = @index["Foo"]
      assert_equal(1, entries.length)
    end

    def test_deleting_all_entries_for_a_class
      @index.index_single("/fake/path/foo.rb", <<~RUBY)
        class Foo
        end
      RUBY

      entries = @index["Foo"]
      assert_equal(1, entries.length)

      @index.delete("/fake/path/foo.rb")
      entries = @index["Foo"]
      assert_nil(entries)
    end

    def test_index_resolve
      @index.index_single("/fake/path/foo.rb", <<~RUBY)
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
      @index.index_single("/fake/path/foo.rb", <<~RUBY)
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
      @index.index_single("/fake/path/foo.rb", <<~RUBY)
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
  end
end
