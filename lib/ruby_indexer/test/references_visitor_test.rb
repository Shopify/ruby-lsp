# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class ReferencesVisitorTest < TestCase
    extend T::Sig

    def test_finding_constant_references
      index(<<~RUBY)
        class Foo
        end
      RUBY

      visitor = ReferencesVisitor.new(@index, "fake.rb", "Foo")
      visitor.visit(YARP.parse("Foo").value)
      assert_reference(visitor, "0:0-0:3")
    end

    def test_finding_constant_path_references
      index(<<~RUBY)
        module Foo
          class Bar
          end
        end
      RUBY

      visitor = ReferencesVisitor.new(@index, "fake.rb", "Foo::Bar")
      visitor.visit(YARP.parse("Foo::Bar").value)
      assert_reference(visitor, "0:0-0:8")
    end

    def test_ignores_invalid_private_constant_accesses
      index(<<~RUBY)
        module Foo
          class Bar
          end
          private_constant :Bar
        end
      RUBY

      visitor = ReferencesVisitor.new(@index, "fake.rb", "Foo::Bar")
      visitor.visit(YARP.parse("Foo::Bar").value)
      assert_empty(visitor.references)

      visitor = ReferencesVisitor.new(@index, "fake.rb", "Foo::Bar")
      visitor.visit(YARP.parse(<<~RUBY).value)
        module Foo
          Bar
        end
      RUBY
      assert_reference(visitor, "1:2-1:5")
    end

    def test_does_not_count_declaration_as_a_reference
      index(<<~RUBY)
        class Foo
        end
      RUBY

      visitor = ReferencesVisitor.new(@index, "fake.rb", "Foo")
      visitor.visit(YARP.parse("class Foo; end").value)
      assert_empty(visitor.references)
    end

    private

    sig { params(visitor: ReferencesVisitor, location_string: String).void }
    def assert_reference(visitor, location_string)
      reference = T.must(visitor.references.first)
      location = reference.location

      start_part, end_part = location_string.split("-")
      start_line, start_column = T.must(start_part).split(":").map(&:to_i)
      end_line, end_column = T.must(end_part).split(":").map(&:to_i)

      assert_equal(start_line, location.start_line - 1)
      assert_equal(start_column, location.start_column)
      assert_equal(end_line, location.end_line - 1)
      assert_equal(end_column, location.end_column)
    end
  end
end
