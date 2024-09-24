# typed: true
# frozen_string_literal: true

require_relative "test_case"

module RubyIndexer
  class MethodTest < TestCase
    def test_method_with_no_parameters
      index(<<~RUBY)
        class Foo
          def bar
          end
        end
      RUBY

      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:1-2:2-5")
    end

    def test_conditional_method
      index(<<~RUBY)
        class Foo
          def bar
          end if condition
        end
      RUBY

      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:1-2:2-5")
    end

    def test_method_with_multibyte_characters
      index(<<~RUBY)
        class Foo
          def こんにちは; end
        end
      RUBY

      assert_entry("こんにちは", Entry::Method, "/fake/path/foo.rb:1-2:1-16")
    end

    def test_singleton_method_using_self_receiver
      index(<<~RUBY)
        class Foo
          def self.bar
          end
        end
      RUBY

      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:1-2:2-5")

      entry = T.must(@index["bar"].first)
      owner = T.must(entry.owner)
      assert_equal("Foo::<Class:Foo>", owner.name)
      assert_instance_of(Entry::SingletonClass, owner)
    end

    def test_singleton_method_using_other_receiver_is_not_indexed
      index(<<~RUBY)
        class Foo
          def String.bar
          end
        end
      RUBY

      assert_no_entry("bar")
    end

    def test_method_under_dynamic_class_or_module
      index(<<~RUBY)
        module Foo
          class self::Bar
            def bar
            end
          end
        end

        module Bar
          def bar
          end
        end
      RUBY

      assert_equal(2, @index["bar"].length)
      first_entry = T.must(@index["bar"].first)
      assert_equal("Foo::self::Bar", first_entry.owner.name)
      second_entry = T.must(@index["bar"].last)
      assert_equal("Bar", second_entry.owner.name)
    end

    def test_visibility_tracking
      index(<<~RUBY)
        private def foo
        end

        def bar; end

        protected

        def baz; end
      RUBY

      assert_entry("foo", Entry::Method, "/fake/path/foo.rb:0-8:1-3", visibility: Entry::Visibility::PRIVATE)
      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:3-0:3-12", visibility: Entry::Visibility::PUBLIC)
      assert_entry("baz", Entry::Method, "/fake/path/foo.rb:7-0:7-12", visibility: Entry::Visibility::PROTECTED)
    end

    def test_visibility_tracking_with_nested_class_or_modules
      index(<<~RUBY)
        class Foo
          private

          def foo; end

          class Bar
            def bar; end
          end

          def baz; end
        end
      RUBY

      assert_entry("foo", Entry::Method, "/fake/path/foo.rb:3-2:3-14", visibility: Entry::Visibility::PRIVATE)
      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:6-4:6-16", visibility: Entry::Visibility::PUBLIC)
      assert_entry("baz", Entry::Method, "/fake/path/foo.rb:9-2:9-14", visibility: Entry::Visibility::PRIVATE)
    end

    def test_method_with_parameters
      index(<<~RUBY)
        class Foo
          def bar(a)
          end
        end
      RUBY

      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:1-2:2-5")
      entry = T.must(@index["bar"].first)
      parameters = entry.signatures.first.parameters
      assert_equal(1, parameters.length)
      parameter = parameters.first
      assert_equal(:a, parameter.name)
      assert_instance_of(Entry::RequiredParameter, parameter)
    end

    def test_method_with_destructed_parameters
      index(<<~RUBY)
        class Foo
          def bar((a, (b, )))
          end
        end
      RUBY

      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:1-2:2-5")
      entry = T.must(@index["bar"].first)
      parameters = entry.signatures.first.parameters
      assert_equal(1, parameters.length)
      parameter = parameters.first
      assert_equal(:"(a, (b, ))", parameter.name)
      assert_instance_of(Entry::RequiredParameter, parameter)
    end

    def test_method_with_optional_parameters
      index(<<~RUBY)
        class Foo
          def bar(a = 123)
          end
        end
      RUBY

      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:1-2:2-5")
      entry = T.must(@index["bar"].first)
      parameters = entry.signatures.first.parameters
      assert_equal(1, parameters.length)
      parameter = parameters.first
      assert_equal(:a, parameter.name)
      assert_instance_of(Entry::OptionalParameter, parameter)
    end

    def test_method_with_keyword_parameters
      index(<<~RUBY)
        class Foo
          def bar(a:, b: 123)
          end
        end
      RUBY

      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:1-2:2-5")
      entry = T.must(@index["bar"].first)
      parameters = entry.signatures.first.parameters
      assert_equal(2, parameters.length)
      a, b = parameters

      assert_equal(:a, a.name)
      assert_instance_of(Entry::KeywordParameter, a)

      assert_equal(:b, b.name)
      assert_instance_of(Entry::OptionalKeywordParameter, b)
    end

    def test_method_with_rest_and_keyword_rest_parameters
      index(<<~RUBY)
        class Foo
          def bar(*a, **b)
          end
        end
      RUBY

      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:1-2:2-5")
      entry = T.must(@index["bar"].first)
      parameters = entry.signatures.first.parameters
      assert_equal(2, parameters.length)
      a, b = parameters

      assert_equal(:a, a.name)
      assert_instance_of(Entry::RestParameter, a)

      assert_equal(:b, b.name)
      assert_instance_of(Entry::KeywordRestParameter, b)
    end

    def test_method_with_post_parameters
      index(<<~RUBY)
        class Foo
          def bar(*a, b)
          end

          def baz(**a, b)
          end

          def qux(*a, (b, c))
        end
      RUBY

      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:1-2:2-5")
      entry = T.must(@index["bar"].first)
      parameters = entry.signatures.first.parameters
      assert_equal(2, parameters.length)
      a, b = parameters

      assert_equal(:a, a.name)
      assert_instance_of(Entry::RestParameter, a)

      assert_equal(:b, b.name)
      assert_instance_of(Entry::RequiredParameter, b)

      entry = T.must(@index["baz"].first)
      parameters = entry.signatures.first.parameters
      assert_equal(2, parameters.length)
      a, b = parameters

      assert_equal(:a, a.name)
      assert_instance_of(Entry::KeywordRestParameter, a)

      assert_equal(:b, b.name)
      assert_instance_of(Entry::RequiredParameter, b)

      entry = T.must(@index["qux"].first)
      parameters = entry.signatures.first.parameters
      assert_equal(2, parameters.length)
      _a, second = parameters

      assert_equal(:"(b, c)", second.name)
      assert_instance_of(Entry::RequiredParameter, second)
    end

    def test_method_with_destructured_rest_parameters
      index(<<~RUBY)
        class Foo
          def bar((a, *b))
          end
        end
      RUBY

      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:1-2:2-5")
      entry = T.must(@index["bar"].first)
      parameters = entry.signatures.first.parameters
      assert_equal(1, parameters.length)
      param = parameters.first

      assert_equal(:"(a, *b)", param.name)
      assert_instance_of(Entry::RequiredParameter, param)
    end

    def test_method_with_block_parameters
      index(<<~RUBY)
        class Foo
          def bar(&block)
          end

          def baz(&)
          end
        end
      RUBY

      entry = T.must(@index["bar"].first)
      parameters = entry.signatures.first.parameters
      param = parameters.first
      assert_equal(:block, param.name)
      assert_instance_of(Entry::BlockParameter, param)

      entry = T.must(@index["baz"].first)
      parameters = entry.signatures.first.parameters
      assert_equal(1, parameters.length)

      param = parameters.first
      assert_equal(Entry::BlockParameter::DEFAULT_NAME, param.name)
      assert_instance_of(Entry::BlockParameter, param)
    end

    def test_method_with_anonymous_rest_parameters
      index(<<~RUBY)
        class Foo
          def bar(*, **)
          end
        end
      RUBY

      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:1-2:2-5")
      entry = T.must(@index["bar"].first)
      parameters = entry.signatures.first.parameters
      assert_equal(2, parameters.length)
      first, second = parameters

      assert_equal(Entry::RestParameter::DEFAULT_NAME, first.name)
      assert_instance_of(Entry::RestParameter, first)

      assert_equal(Entry::KeywordRestParameter::DEFAULT_NAME, second.name)
      assert_instance_of(Entry::KeywordRestParameter, second)
    end

    def test_method_with_forbidden_keyword_splat_parameter
      index(<<~RUBY)
        class Foo
          def bar(**nil)
          end
        end
      RUBY

      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:1-2:2-5")
      entry = T.must(@index["bar"].first)
      parameters = entry.signatures.first.parameters
      assert_empty(parameters)
    end

    def test_methods_with_argument_forwarding
      index(<<~RUBY)
        class Foo
          def bar(...)
          end

          def baz(a, ...)
          end
        end
      RUBY

      entry = T.must(@index["bar"].first)
      assert_instance_of(Entry::Method, entry, "Expected `bar` to be indexed")

      parameters = entry.signatures.first.parameters
      assert_equal(1, parameters.length)
      assert_instance_of(Entry::ForwardingParameter, parameters.first)

      entry = T.must(@index["baz"].first)
      assert_instance_of(Entry::Method, entry, "Expected `baz` to be indexed")

      parameters = entry.signatures.first.parameters
      assert_equal(2, parameters.length)
      assert_instance_of(Entry::RequiredParameter, parameters[0])
      assert_instance_of(Entry::ForwardingParameter, parameters[1])
    end

    def test_keeps_track_of_method_owner
      index(<<~RUBY)
        class Foo
          def bar
          end
        end
      RUBY

      entry = T.must(@index["bar"].first)
      owner_name = T.must(entry.owner).name

      assert_equal("Foo", owner_name)
    end

    def test_keeps_track_of_attributes
      index(<<~RUBY)
        class Foo
          # Hello there
          attr_reader :bar, :other
          attr_writer :baz
          attr_accessor :qux
        end
      RUBY

      assert_entry("bar", Entry::Accessor, "/fake/path/foo.rb:2-15:2-18")
      assert_equal("Hello there", @index["bar"].first.comments)
      assert_entry("other", Entry::Accessor, "/fake/path/foo.rb:2-21:2-26")
      assert_equal("Hello there", @index["other"].first.comments)
      assert_entry("baz=", Entry::Accessor, "/fake/path/foo.rb:3-15:3-18")
      assert_entry("qux", Entry::Accessor, "/fake/path/foo.rb:4-17:4-20")
      assert_entry("qux=", Entry::Accessor, "/fake/path/foo.rb:4-17:4-20")
    end

    def test_ignores_attributes_invoked_on_constant
      index(<<~RUBY)
        class Foo
        end

        Foo.attr_reader :bar
      RUBY

      assert_no_entry("bar")
    end

    def test_properly_tracks_multiple_levels_of_nesting
      index(<<~RUBY)
        module Foo
          def first_method; end

          module Bar
            def second_method; end
          end

          def third_method; end
        end
      RUBY

      entry = T.cast(@index["first_method"]&.first, Entry::Method)
      assert_equal("Foo", T.must(entry.owner).name)

      entry = T.cast(@index["second_method"]&.first, Entry::Method)
      assert_equal("Foo::Bar", T.must(entry.owner).name)

      entry = T.cast(@index["third_method"]&.first, Entry::Method)
      assert_equal("Foo", T.must(entry.owner).name)
    end

    def test_keeps_track_of_aliases
      index(<<~RUBY)
        class Foo
          alias whatever to_s
          alias_method :foo, :to_a
          alias_method "bar", "to_a"

          # These two are not indexed because they are dynamic or incomplete
          alias_method baz, :to_a
          alias_method :baz
        end
      RUBY

      assert_entry("whatever", Entry::UnresolvedMethodAlias, "/fake/path/foo.rb:1-8:1-16")
      assert_entry("foo", Entry::UnresolvedMethodAlias, "/fake/path/foo.rb:2-15:2-19")
      assert_entry("bar", Entry::UnresolvedMethodAlias, "/fake/path/foo.rb:3-15:3-20")
      # Foo plus 3 valid aliases
      assert_equal(4, @index.length - @default_indexed_entries.length)
    end

    def test_singleton_methods
      index(<<~RUBY)
        class Foo
          def self.bar; end

          class << self
            def baz; end
          end
        end
      RUBY

      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:1-2:1-19")
      assert_entry("baz", Entry::Method, "/fake/path/foo.rb:4-4:4-16")

      bar_owner = T.must(T.must(@index["bar"].first).owner)
      baz_owner = T.must(T.must(@index["baz"].first).owner)

      assert_instance_of(Entry::SingletonClass, bar_owner)
      assert_instance_of(Entry::SingletonClass, baz_owner)

      # Regardless of whether the method was added through `self.something` or `class << self`, the owner object must be
      # the exact same
      assert_same(bar_owner, baz_owner)
    end

    def test_name_location_points_to_method_identifier_location
      index(<<~RUBY)
        class Foo
          def bar
            a = 123
            a + 456
          end
        end
      RUBY

      entry = T.must(@index["bar"].first)
      refute_equal(entry.location, entry.name_location)

      name_location = entry.name_location
      assert_equal(2, name_location.start_line)
      assert_equal(2, name_location.end_line)
      assert_equal(6, name_location.start_column)
      assert_equal(9, name_location.end_column)
    end

    def test_signature_matches_for_a_method_with_positional_params
      index(<<~RUBY)
        class Foo
          def bar(a, b = 123)
          end
        end
      RUBY

      entry = T.must(@index["bar"].first)

      # Matching calls
      assert_signature_matches(entry, "bar()")
      assert_signature_matches(entry, "bar(1)")
      assert_signature_matches(entry, "bar(1, 2)")
      assert_signature_matches(entry, "bar(...)")
      assert_signature_matches(entry, "bar(1, ...)")
      assert_signature_matches(entry, "bar(*a)")
      assert_signature_matches(entry, "bar(1, *a)")
      assert_signature_matches(entry, "bar(1, *a, 2)")
      assert_signature_matches(entry, "bar(*a, 2)")
      assert_signature_matches(entry, "bar(1, **a)")
      assert_signature_matches(entry, "bar(1) {}")
      # This call is impossible to analyze statically because it depends on whether there are elements inside `a` or
      # not. If there's nothing, the call will fail. But if there's anything inside, the hash will become the first
      # positional argument
      assert_signature_matches(entry, "bar(**a)")

      # Non matching calls

      refute_signature_matches(entry, "bar(1, 2, 3)")
      refute_signature_matches(entry, "bar(1, b: 2)")
      refute_signature_matches(entry, "bar(1, 2, c: 3)")
    end

    def test_signature_matches_for_a_method_with_argument_forwarding
      index(<<~RUBY)
        class Foo
          def bar(...)
          end
        end
      RUBY

      entry = T.must(@index["bar"].first)

      # All calls match a forwarding parameter
      assert_signature_matches(entry, "bar(1)")
      assert_signature_matches(entry, "bar(1, 2)")
      assert_signature_matches(entry, "bar(...)")
      assert_signature_matches(entry, "bar(1, ...)")
      assert_signature_matches(entry, "bar(*a)")
      assert_signature_matches(entry, "bar(1, *a)")
      assert_signature_matches(entry, "bar(1, *a, 2)")
      assert_signature_matches(entry, "bar(*a, 2)")
      assert_signature_matches(entry, "bar(1, **a)")
      assert_signature_matches(entry, "bar(1) {}")
      assert_signature_matches(entry, "bar()")
      assert_signature_matches(entry, "bar(1, 2, 3)")
      assert_signature_matches(entry, "bar(1, 2, a: 1, b: 5) {}")
    end

    def test_signature_matches_for_post_forwarding_parameter
      index(<<~RUBY)
        class Foo
          def bar(a, ...)
          end
        end
      RUBY

      entry = T.must(@index["bar"].first)

      # All calls with at least one positional argument match
      assert_signature_matches(entry, "bar(1)")
      assert_signature_matches(entry, "bar(1, 2)")
      assert_signature_matches(entry, "bar(...)")
      assert_signature_matches(entry, "bar(1, ...)")
      assert_signature_matches(entry, "bar(*a)")
      assert_signature_matches(entry, "bar(1, *a)")
      assert_signature_matches(entry, "bar(1, *a, 2)")
      assert_signature_matches(entry, "bar(*a, 2)")
      assert_signature_matches(entry, "bar(1, **a)")
      assert_signature_matches(entry, "bar(1) {}")
      assert_signature_matches(entry, "bar(1, 2, 3)")
      assert_signature_matches(entry, "bar(1, 2, a: 1, b: 5) {}")
      assert_signature_matches(entry, "bar()")
    end

    def test_signature_matches_for_destructured_parameters
      index(<<~RUBY)
        class Foo
          def bar(a, (b, c))
          end
        end
      RUBY

      entry = T.must(@index["bar"].first)

      # All calls with at least one positional argument match
      assert_signature_matches(entry, "bar()")
      assert_signature_matches(entry, "bar(1)")
      assert_signature_matches(entry, "bar(1, 2)")
      assert_signature_matches(entry, "bar(...)")
      assert_signature_matches(entry, "bar(1, ...)")
      assert_signature_matches(entry, "bar(*a)")
      assert_signature_matches(entry, "bar(1, *a)")
      assert_signature_matches(entry, "bar(*a, 2)")
      # This matches because `bar(1, *[], 2)` would result in `bar(1, 2)`, which is a valid call
      assert_signature_matches(entry, "bar(1, *a, 2)")
      assert_signature_matches(entry, "bar(1, **a)")
      assert_signature_matches(entry, "bar(1) {}")

      refute_signature_matches(entry, "bar(1, 2, 3)")
      refute_signature_matches(entry, "bar(1, 2, a: 1, b: 5) {}")
    end

    def test_signature_matches_for_post_parameters
      index(<<~RUBY)
        class Foo
          def bar(*splat, a)
          end
        end
      RUBY

      entry = T.must(@index["bar"].first)

      # All calls with at least one positional argument match
      assert_signature_matches(entry, "bar(1)")
      assert_signature_matches(entry, "bar(1, 2)")
      assert_signature_matches(entry, "bar(...)")
      assert_signature_matches(entry, "bar(1, ...)")
      assert_signature_matches(entry, "bar(*a)")
      assert_signature_matches(entry, "bar(1, *a)")
      assert_signature_matches(entry, "bar(*a, 2)")
      assert_signature_matches(entry, "bar(1, *a, 2)")
      assert_signature_matches(entry, "bar(1, **a)")
      assert_signature_matches(entry, "bar(1, 2, 3)")
      assert_signature_matches(entry, "bar(1) {}")
      assert_signature_matches(entry, "bar()")

      refute_signature_matches(entry, "bar(1, 2, a: 1, b: 5) {}")
    end

    def test_signature_matches_for_keyword_parameters
      index(<<~RUBY)
        class Foo
          def bar(a:, b: 123)
          end
        end
      RUBY

      entry = T.must(@index["bar"].first)

      assert_signature_matches(entry, "bar(...)")
      assert_signature_matches(entry, "bar()")
      assert_signature_matches(entry, "bar(a: 1)")
      assert_signature_matches(entry, "bar(a: 1, b: 32)")

      refute_signature_matches(entry, "bar(a: 1, c: 2)")
      refute_signature_matches(entry, "bar(1, ...)")
      refute_signature_matches(entry, "bar(1) {}")
      refute_signature_matches(entry, "bar(1, *a)")
      refute_signature_matches(entry, "bar(*a, 2)")
      refute_signature_matches(entry, "bar(1, *a, 2)")
      refute_signature_matches(entry, "bar(1, **a)")
      refute_signature_matches(entry, "bar(*a)")
      refute_signature_matches(entry, "bar(1)")
      refute_signature_matches(entry, "bar(1, 2)")
      refute_signature_matches(entry, "bar(1, 2, a: 1, b: 5) {}")
    end

    def test_signature_matches_for_keyword_splats
      index(<<~RUBY)
        class Foo
          def bar(a, b:, **kwargs)
          end
        end
      RUBY

      entry = T.must(@index["bar"].first)

      assert_signature_matches(entry, "bar(...)")
      assert_signature_matches(entry, "bar()")
      assert_signature_matches(entry, "bar(1)")
      assert_signature_matches(entry, "bar(1, b: 2)")
      assert_signature_matches(entry, "bar(1, b: 2, c: 3, d: 4)")

      refute_signature_matches(entry, "bar(1, 2, b: 2)")
    end

    def test_partial_signature_matches
      # It's important to match signatures partially, because we want to figure out which signature we should show while
      # the user is in the middle of typing
      index(<<~RUBY)
        class Foo
          def bar(a:, b:)
          end

          def baz(a, b)
          end
        end
      RUBY

      entry = T.must(@index["bar"].first)
      assert_signature_matches(entry, "bar(a: 1)")

      entry = T.must(@index["baz"].first)
      assert_signature_matches(entry, "baz(1)")
    end

    private

    sig { params(entry: Entry::Method, call_string: String).void }
    def assert_signature_matches(entry, call_string)
      sig = T.must(entry.signatures.first)
      arguments = parse_prism_args(call_string)
      assert(sig.matches?(arguments), "Expected #{call_string} to match #{entry.name}#{entry.decorated_parameters}")
    end

    sig { params(entry: Entry::Method, call_string: String).void }
    def refute_signature_matches(entry, call_string)
      sig = T.must(entry.signatures.first)
      arguments = parse_prism_args(call_string)
      refute(sig.matches?(arguments), "Expected #{call_string} to not match #{entry.name}#{entry.decorated_parameters}")
    end

    def parse_prism_args(s)
      Array(Prism.parse(s).value.statements.body.first.arguments&.arguments)
    end
  end
end
