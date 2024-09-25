# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyIndexer
  class ReferenceFinderTest < Minitest::Test
    def test_finds_constant_references
      refs = find_references("Foo::Bar", <<~RUBY)
        module Foo
          class Bar
          end

          Bar
        end

        Foo::Bar
      RUBY

      assert_equal("Bar", refs[0].name)
      assert_equal(2, refs[0].location.start_line)

      assert_equal("Bar", refs[1].name)
      assert_equal(5, refs[1].location.start_line)

      assert_equal("Foo::Bar", refs[2].name)
      assert_equal(8, refs[2].location.start_line)
    end

    def test_finds_constant_references_inside_singleton_contexts
      refs = find_references("Foo::<Class:Foo>::Bar", <<~RUBY)
        class Foo
          class << self
            class Bar
            end

            Bar
          end
        end
      RUBY

      assert_equal("Bar", refs[0].name)
      assert_equal(3, refs[0].location.start_line)

      assert_equal("Bar", refs[1].name)
      assert_equal(6, refs[1].location.start_line)
    end

    def test_finds_top_level_constant_references
      refs = find_references("Bar", <<~RUBY)
        class Bar
        end

        class Foo
          ::Bar

          class << self
            ::Bar
          end
        end
      RUBY

      assert_equal("Bar", refs[0].name)
      assert_equal(1, refs[0].location.start_line)

      assert_equal("::Bar", refs[1].name)
      assert_equal(5, refs[1].location.start_line)

      assert_equal("::Bar", refs[2].name)
      assert_equal(8, refs[2].location.start_line)
    end

    private

    def find_references(fully_qualified_name, source)
      file_path = "/fake.rb"
      index = Index.new
      index.index_single(IndexablePath.new(nil, file_path), source)
      parse_result = Prism.parse(source)
      dispatcher = Prism::Dispatcher.new
      finder = ReferenceFinder.new(fully_qualified_name, index, dispatcher)
      dispatcher.visit(parse_result.value)
      finder.references.uniq(&:location)
    end
  end
end
