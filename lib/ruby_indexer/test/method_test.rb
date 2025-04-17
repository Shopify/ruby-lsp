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

      entry = @index["bar"]&.first #: as Entry::Method
      owner = entry.owner
      assert_equal("Foo::<Class:Foo>", owner&.name)
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

      assert_equal(2, @index["bar"]&.length)
      first_entry = @index["bar"]&.first #: as Entry::Method
      assert_equal("Foo::self::Bar", first_entry.owner&.name)
      second_entry = @index["bar"]&.last #: as Entry::Method
      assert_equal("Bar", second_entry.owner&.name)
    end

    def test_visibility_tracking
      index(<<~RUBY)
        class Foo
          private def foo
          end

          def bar; end

          protected

          def baz; end
        end
      RUBY

      assert_entry("foo", Entry::Method, "/fake/path/foo.rb:1-10:2-5", visibility: Entry::Visibility::PRIVATE)
      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:4-2:4-14", visibility: Entry::Visibility::PUBLIC)
      assert_entry("baz", Entry::Method, "/fake/path/foo.rb:8-2:8-14", visibility: Entry::Visibility::PROTECTED)
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

    def test_visibility_tracking_with_module_function
      index(<<~RUBY)
        module Test
          def foo; end
          def bar; end
          module_function :foo, "bar"
        end
      RUBY

      ["foo", "bar"].each do |keyword|
        entries = @index[keyword] #: as Array[Entry::Method]
        # should receive two entries because module_function creates a singleton method
        # for the Test module and a private method for classes include the Test module
        assert_equal(entries.size, 2)
        first_entry, second_entry = *entries
        # The first entry points to the location of the module_function call
        assert_equal("Test", first_entry&.owner&.name)
        assert_instance_of(Entry::Module, first_entry&.owner)
        assert_predicate(first_entry, :private?)
        # The second entry points to the public singleton method
        assert_equal("Test::<Class:Test>", second_entry&.owner&.name)
        assert_instance_of(Entry::SingletonClass, second_entry&.owner)
        assert_equal(Entry::Visibility::PUBLIC, second_entry&.visibility)
      end
    end

    def test_private_class_method_visibility_tracking_string_symbol_arguments
      index(<<~RUBY)
        class Test
          def self.foo
          end

          def self.bar
          end

          private_class_method("foo", :bar)

          def self.baz
          end
        end
      RUBY

      ["foo", "bar"].each do |keyword|
        entries = @index[keyword] #: as Array[Entry::Method]
        assert_equal(1, entries.size)
        entry = entries.first
        assert_predicate(entry, :private?)
      end

      entries = @index["baz"] #: as Array[Entry::Method]
      assert_equal(1, entries.size)
      entry = entries.first
      assert_predicate(entry, :public?)
    end

    def test_private_class_method_visibility_tracking_array_argument
      index(<<~RUBY)
        class Test
          def self.foo
          end

          def self.bar
          end

          private_class_method(["foo", :bar])

          def self.baz
          end
        end
      RUBY

      ["foo", "bar"].each do |keyword|
        entries = @index[keyword] #: as Array[Entry::Method]
        assert_equal(1, entries.size)
        entry = entries.first
        assert_predicate(entry, :private?)
      end

      entries = @index["baz"] #: as Array[Entry::Method]
      assert_equal(1, entries.size)
      entry = entries.first
      assert_predicate(entry, :public?)
    end

    def test_private_class_method_visibility_tracking_method_argument
      index(<<~RUBY)
        class Test
          private_class_method def self.foo
          end

          def self.bar
          end
        end
      RUBY

      entries = @index["foo"] #: as Array[Entry::Method]
      assert_equal(1, entries.size)
      entry = entries.first
      assert_predicate(entry, :private?)

      entries = @index["bar"] #: as Array[Entry::Method]
      assert_equal(1, entries.size)
      entry = entries.first
      assert_predicate(entry, :public?)
    end

    def test_comments_documentation
      index(<<~RUBY)
        # Documentation for Foo

        class Foo
          # ####################
          # Documentation for bar
          # ####################
          #
          def bar
          end

          # test

          # Documentation for baz
          def baz; end
          def ban; end
        end
      RUBY

      foo = @index["Foo"]&.first #: as !nil
      assert_equal("Documentation for Foo", foo.comments)

      bar = @index["bar"]&.first #: as !nil
      assert_equal("####################\nDocumentation for bar\n####################\n", bar.comments)

      baz = @index["baz"]&.first #: as !nil
      assert_equal("Documentation for baz", baz.comments)

      ban = @index["ban"]&.first #: as !nil
      assert_empty(ban.comments)
    end

    def test_method_with_parameters
      index(<<~RUBY)
        class Foo
          def bar(a)
          end
        end
      RUBY

      assert_entry("bar", Entry::Method, "/fake/path/foo.rb:1-2:2-5")
      entry = @index["bar"]&.first #: as Entry::Method
      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
      assert_equal(1, parameters.length)
      parameter = parameters.first
      assert_equal(:a, parameter&.name)
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
      entry = @index["bar"]&.first #: as Entry::Method
      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
      assert_equal(1, parameters.length)
      parameter = parameters.first
      assert_equal(:"(a, (b, ))", parameter&.name)
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
      entry = @index["bar"]&.first #: as Entry::Method
      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
      assert_equal(1, parameters.length)
      parameter = parameters.first
      assert_equal(:a, parameter&.name)
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
      entry = @index["bar"]&.first #: as Entry::Method
      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
      assert_equal(2, parameters.length)
      a, b = parameters

      assert_equal(:a, a&.name)
      assert_instance_of(Entry::KeywordParameter, a)

      assert_equal(:b, b&.name)
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
      entry = @index["bar"]&.first #: as Entry::Method
      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
      assert_equal(2, parameters.length)
      a, b = parameters

      assert_equal(:a, a&.name)
      assert_instance_of(Entry::RestParameter, a)

      assert_equal(:b, b&.name)
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
      entry = @index["bar"]&.first #: as Entry::Method
      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
      assert_equal(2, parameters.length)
      a, b = parameters

      assert_equal(:a, a&.name)
      assert_instance_of(Entry::RestParameter, a)

      assert_equal(:b, b&.name)
      assert_instance_of(Entry::RequiredParameter, b)

      entry = @index["baz"]&.first #: as Entry::Method
      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
      assert_equal(2, parameters.length)
      a, b = parameters

      assert_equal(:a, a&.name)
      assert_instance_of(Entry::KeywordRestParameter, a)

      assert_equal(:b, b&.name)
      assert_instance_of(Entry::RequiredParameter, b)

      entry = @index["qux"]&.first #: as Entry::Method
      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
      assert_equal(2, parameters.length)
      _a, second = parameters

      assert_equal(:"(b, c)", second&.name)
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
      entry = @index["bar"]&.first #: as Entry::Method
      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
      assert_equal(1, parameters.length)
      param = parameters.first #: as Entry::Parameter

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

      entry = @index["bar"]&.first #: as Entry::Method
      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
      param = parameters.first #: as Entry::Parameter
      assert_equal(:block, param.name)
      assert_instance_of(Entry::BlockParameter, param)

      entry = @index["baz"]&.first #: as Entry::Method
      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
      assert_equal(1, parameters.length)

      param = parameters.first #: as Entry::Parameter
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
      entry = @index["bar"]&.first #: as Entry::Method
      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
      assert_equal(2, parameters.length)
      first, second = parameters

      assert_equal(Entry::RestParameter::DEFAULT_NAME, first&.name)
      assert_instance_of(Entry::RestParameter, first)

      assert_equal(Entry::KeywordRestParameter::DEFAULT_NAME, second&.name)
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
      entry = @index["bar"]&.first #: as Entry::Method
      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
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

      entry = @index["bar"]&.first #: as Entry::Method
      assert_instance_of(Entry::Method, entry, "Expected `bar` to be indexed")

      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
      assert_equal(1, parameters.length)
      assert_instance_of(Entry::ForwardingParameter, parameters.first)

      entry = @index["baz"]&.first #: as Entry::Method
      assert_instance_of(Entry::Method, entry, "Expected `baz` to be indexed")

      parameters = entry.signatures.first&.parameters #: as Array[Entry::Parameter]
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

      entry = @index["bar"]&.first #: as Entry::Method
      owner_name = entry.owner&.name

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
      assert_equal("Hello there", @index["bar"]&.first&.comments)
      assert_entry("other", Entry::Accessor, "/fake/path/foo.rb:2-21:2-26")
      assert_equal("Hello there", @index["other"]&.first&.comments)
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

      entry = @index["first_method"]&.first #: as Entry::Method
      assert_equal("Foo", entry.owner&.name)

      entry = @index["second_method"]&.first #: as Entry::Method
      assert_equal("Foo::Bar", entry.owner&.name)

      entry = @index["third_method"]&.first #: as Entry::Method
      assert_equal("Foo", entry.owner&.name)
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

      bar = @index["bar"]&.first #: as Entry::Method
      baz = @index["baz"]&.first #: as Entry::Method

      assert_instance_of(Entry::SingletonClass, bar.owner)
      assert_instance_of(Entry::SingletonClass, baz.owner)

      # Regardless of whether the method was added through `self.something` or `class << self`, the owner object must be
      # the exact same
      assert_same(bar.owner, baz.owner)
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

      entry = @index["bar"]&.first #: as Entry::Method
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

      entry = @index["bar"]&.first #: as Entry::Method

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

      entry = @index["bar"]&.first #: as Entry::Method

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

      entry = @index["bar"]&.first #: as Entry::Method

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

      entry = @index["bar"]&.first #: as Entry::Method

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

      entry = @index["bar"]&.first #: as Entry::Method

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

      entry = @index["bar"]&.first #: as Entry::Method

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

      entry = @index["bar"]&.first #: as Entry::Method

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

      entry = @index["bar"]&.first #: as Entry::Method
      assert_signature_matches(entry, "bar(a: 1)")

      entry = @index["baz"]&.first #: as Entry::Method
      assert_signature_matches(entry, "baz(1)")
    end

    def test_module_function_with_no_arguments
      index(<<~RUBY)
        module Foo
          def bar; end

          module_function

          def baz; end
          attr_reader :attribute

          public

          def qux; end
        end
      RUBY

      entry = @index["bar"]&.first #: as Entry::Method
      assert_predicate(entry, :public?)
      assert_equal("Foo", entry.owner&.name)

      instance_baz, singleton_baz = @index["baz"] #: as Array[Entry::Method]
      assert_predicate(instance_baz, :private?)
      assert_equal("Foo", instance_baz&.owner&.name)

      assert_predicate(singleton_baz, :public?)
      assert_equal("Foo::<Class:Foo>", singleton_baz&.owner&.name)

      # After invoking `public`, the state of `module_function` is reset
      instance_qux, singleton_qux = @index["qux"] #: as Array[Entry::Method]
      assert_nil(singleton_qux)
      assert_predicate(instance_qux, :public?)
      assert_equal("Foo", instance_baz&.owner&.name)

      # Attributes are not turned into class methods, they do become private
      instance_attribute, singleton_attribute = @index["attribute"] #: as Array[Entry::Method]
      assert_nil(singleton_attribute)
      assert_equal("Foo", instance_attribute&.owner&.name)
      assert_predicate(instance_attribute, :private?)
    end

    def test_module_function_does_nothing_in_classes
      # Invoking `module_function` in a class raises an error. We simply ignore it
      index(<<~RUBY)
        class Foo
          def bar; end

          module_function

          def baz; end
        end
      RUBY

      entry = @index["bar"]&.first #: as Entry::Method
      assert_predicate(entry, :public?)
      assert_equal("Foo", entry.owner&.name)

      entry = @index["baz"]&.first #: as Entry::Method
      assert_predicate(entry, :public?)
      assert_equal("Foo", entry.owner&.name)
    end

    def test_making_several_class_methods_private
      index(<<~RUBY)
        class Foo
          def self.bar; end
          def self.baz; end
          def self.qux; end

          private_class_method :bar, :baz, :qux

          def initialize
          end
        end
      RUBY
    end

    def test_changing_visibility_post_definition
      index(<<~RUBY)
        class Foo
          def bar; end
          private :bar

          def baz; end
          protected :baz

          private
          def qux; end

          public :qux
        end
      RUBY

      entry = @index["bar"]&.first #: as Entry::Method
      assert_predicate(entry, :private?)

      entry = @index["baz"]&.first #: as Entry::Method
      assert_predicate(entry, :protected?)

      entry = @index["qux"]&.first #: as Entry::Method
      assert_predicate(entry, :public?)
    end

    private

    #: (Entry::Method entry, String call_string) -> void
    def assert_signature_matches(entry, call_string)
      sig = entry.signatures.first #: as !nil
      arguments = parse_prism_args(call_string)
      assert(sig.matches?(arguments), "Expected #{call_string} to match #{entry.name}#{entry.decorated_parameters}")
    end

    #: (Entry::Method entry, String call_string) -> void
    def refute_signature_matches(entry, call_string)
      sig = entry.signatures.first #: as !nil
      arguments = parse_prism_args(call_string)
      refute(sig.matches?(arguments), "Expected #{call_string} to not match #{entry.name}#{entry.decorated_parameters}")
    end

    def parse_prism_args(s)
      Array(Prism.parse(s).value.statements.body.first.arguments&.arguments)
    end
  end
end
