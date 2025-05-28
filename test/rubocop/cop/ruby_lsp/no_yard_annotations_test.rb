# typed: true
# frozen_string_literal: true

require "test_helper"

require "rubocop-minitest"
require "rubocop/minitest/assert_offense"

class NoYardAnnotationsTest < Minitest::Test
  include RuboCop::Minitest::AssertOffense

  def setup
    @cop = ::RuboCop::Cop::RubyLsp::NoYardAnnotations.new
  end

  def test_does_not_register_offense_for_regular_comments
    assert_no_offenses(<<~RUBY)
      class Example
        # This is a regular comment
        # TODO: This is a regular todo (not YARD)
        # NOTE: This is a regular note (not YARD)
        def greet(name)
          "Hello \#{name}"
        end
      end
    RUBY
  end

  def test_registers_offense_for_param_annotation
    assert_offense(<<~RUBY)
      class Example
        # @param name [String] the name
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        def greet(name)
          "Hello \#{name}"
        end
      end
    RUBY
  end

  def test_registers_offense_for_return_annotation
    assert_offense(<<~RUBY)
      class Example
        # @return [String] the greeting
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        def greet(name)
          "Hello \#{name}"
        end
      end
    RUBY
  end

  def test_registers_offense_for_multiple_param_annotations_with_wrapped_lines
    assert_offense(<<~RUBY)
      class Example
        # @param first_name [String] the first name
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        #   of the person
        # @param last_name [String] the last name
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        #    of the person
        # @return [String] the full name for
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        #   the person
        def full_name(first_name, last_name)
          "\#{first_name} \#{last_name}"
        end
      end
    RUBY
  end

  def test_registers_offense_for_yield_annotations
    assert_offense(<<~RUBY)
      class Example
        # @yield [value] yields the processed value
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        # @yieldparam value [String] the value to process
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        # @yieldreturn [String] the processed result
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        def process_value(value)
          yield(value)
        end
      end
    RUBY
  end

  def test_registers_offense_for_overload_annotation
    assert_offense(<<~RUBY)
      class Example
        # @overload greet(name)
        ^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        #   @param name [String]
        #   @return [String]
        # @overload greet(first, last)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        #   @param first [String]
        #   @param last [String]
        #   @return [String]
        def greet(*args)
          # implementation
        end
      end
    RUBY
  end

  def test_registers_offense_for_option_annotation
    assert_offense(<<~RUBY)
      class Example
        # @option opts [String] :name The name
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        # @option opts [Integer] :age The age
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        def process_options(opts = {})
          # implementation
        end
      end
    RUBY
  end

  def test_registers_offense_for_mixed_yard_and_regular_comments
    assert_offense(<<~RUBY)
      class Example
        # This is a regular comment
        # @param name [String] the name
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        # Another regular comment
        # @return [String] the greeting
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        # Final comment
        def greet(name)
          "Hello \#{name}"
        end
      end
    RUBY
  end

  def test_does_not_register_offense_for_yard_like_tag_inside_comment_line
    assert_no_offenses(<<~RUBY)
      class Example
        # This is a comment with a tag @param but not a YARD annotation
        # This is a comment with a tag @return but not a YARD annotation
        # This is a comment with a tag @option but not a YARD annotation
        # This is a comment with a tag @overload but not a YARD annotation
        # This is a comment with a tag @yield but not a YARD annotation
        # This is a comment with a tag @yieldparam but not a YARD annotation
        # This is a comment with a tag @yieldreturn but not a YARD annotation
        def greet(name)
          "Hello \#{name}"
        end
      end
    RUBY
  end

  def test_registers_offense_for_yard_annotation_with_extra_spaces
    assert_offense(<<~RUBY)
      class Example
        #   @param name [String] the name with extra spaces
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        #    @return [String] the greeting with extra spaces
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        def greet(name)
          "Hello \#{name}"
        end
      end
    RUBY
  end

  def test_registers_offense_for_yard_annotation_but_skips_wrapped_lines
    assert_offense(<<~RUBY)
      class Example
        # @param name [String] the name with extra spaces
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RubyLsp/NoYardAnnotations: Avoid using YARD method annotations. Use RBS comment syntax instead.
        #   @return [String] the greeting with extra spaces
        #   No error on return because it's wrapped and part of the @param
        def greet(name)
          "Hello \#{name}"
        end
      end
    RUBY
  end
end
