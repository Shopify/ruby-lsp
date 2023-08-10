# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyIndexer
  class IndexTest < Minitest::Test
    def setup
      @index = Index.new
    end

    def teardown
      @index.clear
    end

    def test_deleting_one_entry_for_a_class
      RubyIndexer.index_single(@index, "/fake/path/foo.rb", <<~RUBY)
        class Foo
        end
      RUBY
      RubyIndexer.index_single(@index, "/fake/path/other_foo.rb", <<~RUBY)
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
      RubyIndexer.index_single(@index, "/fake/path/foo.rb", <<~RUBY)
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
      RubyIndexer.index_single(@index, "/fake/path/foo.rb", <<~RUBY)
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
      RubyIndexer.index_single(@index, "/fake/path/foo.rb", <<~RUBY)
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
  end
end
