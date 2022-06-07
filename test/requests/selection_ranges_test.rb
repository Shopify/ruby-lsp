# typed: true
# frozen_string_literal: true

require "test_helper"

class SelectionRangesTest < Minitest::Test
  def test_selecting_single_line_method_definitions
    fixture = <<~RUBY
      def foo; end
      def bar; end
      def baz; end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 0, character: 0 }],
      [{ range: {
        start: { line: 0, character: 0 },
        end: { line: 0, character: 12 },
      } }]
    )
  end

  def test_selecting_method_definitions
    fixture = <<~RUBY
      def foo(a, b)
        x = 2
        puts "x"
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 0, character: 0 }],
      [{ range: {
        start: { line: 0, character: 0 },
        end: { line: 3, character: 3 },
      } }]
    )

    assert_ranges(
      fixture,
      [{ line: 0, character: 8 }],
      [{
        range: {
          start: { line: 0, character: 8 },
          end: { line: 0, character: 9 },
        },
        parent: {
          range: {
            start: { line: 0, character: 8 },
            end: { line: 0, character: 12 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 3, character: 3 },
            },
          },
        },
      }]
    )

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 1, character: 3 },
        },
        parent: {
          range: {
            start: { line: 1, character: 2 },
            end: { line: 1, character: 7 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 3, character: 3 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_long_params_method_definitions
    fixture = <<~RUBY
      def foo(
        a,
        b
      )
        a = 2
        puts "a"
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 0, character: 0 }],
      [{ range: {
        start: { line: 0, character: 0 },
        end: { line: 6, character: 3 },
      } }]
    )

    # NOTE: ask Kevin Newton about syntax-tree parser.rb line 1958; it seems like this might
    # be a bug in syntax tree, where it sets the start and end chars of the Params node to be
    # the left and right parens respectively. Not sure if this is on purpose or a bug.
    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 1, character: 3 },
        },
        parent: {
          range: {
            start: { line: 1, character: 8 },
            end: { line: 2, character: 0 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 6, character: 3 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_singleton_method_definitions
    fixture = <<~RUBY
      def self.foo
        a = 2
        puts "a"
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 0, character: 0 }],
      [{ range: {
        start: { line: 0, character: 0 },
        end: { line: 3, character: 3 },
      } }]
    )

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 1, character: 3 },
        },
        parent: {
          range: {
            start: { line: 1, character: 2 },
            end: { line: 1, character: 7 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 3, character: 3 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_classes
    fixture = <<~RUBY
      class Foo
        def bar
          puts "Hello!"
        end
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 0, character: 0 }],
      [{ range: {
        start: { line: 0, character: 0 },
        end: { line: 4, character: 3 },
      } }]
    )

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 3, character: 5 },
        },
        parent: {
          range: {
            start: { line: 0, character: 0 },
            end: { line: 4, character: 3 },
          },
        },
      }]
    )

    assert_ranges(
      fixture,
      [{ line: 2, character: 4 }],
      [{
        range: {
          start: { line: 2, character: 4 },
          end: { line: 2, character: 8 },
        },
        parent: {
          range: {
            start: { line: 2, character: 4 },
            end: { line: 2, character: 17 },
          },
          parent: {
            range: {
              start: { line: 1, character: 2 },
              end: { line: 3, character: 5 },
            },
            parent: {
              range: {
                start: { line: 0, character: 0 },
                end: { line: 4, character: 3 },
              },
            },
          },
        },
      }]
    )
  end

  def test_selecting_singleton_classes
    fixture = <<~RUBY
      class Foo
        class << self
        end
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 0, character: 0 }],
      [{ range: {
        start: { line: 0, character: 0 },
        end: { line: 3, character: 3 },
      } }]
    )

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 2, character: 5 },
        },
        parent: {
          range: {
            start: { line: 0, character: 0 },
            end: { line: 3, character: 3 },
          },
        },
      }]
    )
  end

  def test_selecting_modules
    fixture = <<~RUBY
      module Foo
        class Bar
        end

        module Baz
        end
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 0, character: 0 }],
      [{ range: {
        start: { line: 0, character: 0 },
        end: { line: 6, character: 3 },
      } }]
    )

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 2, character: 5 },
        },
        parent: {
          range: {
            start: { line: 0, character: 0 },
            end: { line: 6, character: 3 },
          },
        },
      }]
    )
  end

  def test_selecting_do_blocks
    fixture = <<~RUBY
      list.each do |item|
        puts item
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 0, character: 10 }],
      [{
        range: {
          start: { line: 0, character: 10 },
          end: { line: 0, character: 12 },
        },
        parent: {
          range: {
            start: { line: 0, character: 10 },
            end: { line: 2, character: 3 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 2, character: 3 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_multiline_block
    fixture = <<~RUBY
      list.each { |item|
        puts item
      }
    RUBY

    assert_ranges(
      fixture,
      [{ line: 0, character: 10 }],
      [{
        range: {
          start: { line: 0, character: 10 },
          end: { line: 0, character: 11 },
        },
        parent: {
          range: {
            start: { line: 0, character: 10 },
            end: { line: 2, character: 1 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 2, character: 1 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_lambdas
    fixture = <<~RUBY
      lambda { |item|
        puts item
      }
    RUBY

    assert_ranges(
      fixture,
      [{ line: 0, character: 0 }],
      [{
        range: {
          start: { line: 0, character: 0 },
          end: { line: 0, character: 6 },
        },
        parent: {
          range: {
            start: { line: 0, character: 0 },
            end: { line: 0, character: 6 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 2, character: 1 },
            },
          },
        },
      }]
    )

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 1, character: 6 },
        },
        parent: {
          range: {
            start: { line: 1, character: 2 },
            end: { line: 1, character: 11 },
          },
          parent: {
            range: {
              start: { line: 0, character: 7 },
              end: { line: 2, character: 1 },
            },
            parent: {
              range: {
                start: { line: 0, character: 0 },
                end: { line: 2, character: 1 },
              },
            },
          },
        },
      }]
    )
  end

  def test_selecting_single_line_arrays
    fixture = <<~RUBY
      a = [1, 2]
    RUBY

    assert_ranges(
      fixture,
      [{ line: 0, character: 5 }],
      [{
        range: {
          start: { line: 0, character: 5 },
          end: { line: 0, character: 6 },
        },
        parent: {
          range: {
            start: { line: 0, character: 4 },
            end: { line: 0, character: 10 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 0, character: 10 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_multiline_arrays
    fixture = <<~RUBY
      a = [
        1,
        2
      ]
    RUBY

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 1, character: 3 },
        },
        parent: {
          range: {
            start: { line: 0, character: 4 },
            end: { line: 3, character: 1 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 3, character: 1 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_single_line_hashes
    fixture = <<~RUBY
      a = { b: 1, c: 2 }
    RUBY

    assert_ranges(
      fixture,
      [{ line: 0, character: 6 }],
      [{
        range: {
          start: { line: 0, character: 6 },
          end: { line: 0, character: 8 },
        },
        parent: {
          range: {
            start: { line: 0, character: 4 },
            end: { line: 0, character: 18 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 0, character: 18 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_multiline_hashes
    fixture = <<~RUBY
      a = {
        b: 1,
        c: 2
      }
    RUBY

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 1, character: 4 },
        },
        parent: {
          range: {
            start: { line: 0, character: 4 },
            end: { line: 3, character: 1 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 3, character: 1 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_multiline_if_statements
    fixture = <<~RUBY
      if true
        puts "Hello!"
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 1, character: 6 },
        },
        parent: {
          range: {
            start: { line: 1, character: 2 },
            end: { line: 1, character: 15 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 2, character: 3 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_multiline_unless_statements
    fixture = <<~RUBY
      unless true
        puts "Hello!"
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 1, character: 6 },
        },
        parent: {
          range: {
            start: { line: 1, character: 2 },
            end: { line: 1, character: 15 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 2, character: 3 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_while
    fixture = <<~RUBY
      while true
        puts "Hello!"
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 1, character: 6 },
        },
        parent: {
          range: {
            start: { line: 1, character: 2 },
            end: { line: 1, character: 15 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 2, character: 3 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_until
    fixture = <<~RUBY
      until false
        puts "Hello!"
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 1, character: 6 },
        },
        parent: {
          range: {
            start: { line: 1, character: 2 },
            end: { line: 1, character: 15 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 2, character: 3 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_for_loop
    fixture = <<~RUBY
      for i in 0..10
        puts "Hello!"
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 1, character: 6 },
        },
        parent: {
          range: {
            start: { line: 1, character: 2 },
            end: { line: 1, character: 15 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 2, character: 3 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_multiline_function_invocation
    fixture = <<~RUBY
      invocation(
        a: 1,
        b: 2,
      )
    RUBY

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 1, character: 4 },
        },
        # The fact that this doesn't have more parents feels wrong to me...
        parent: {
          range: {
            start: { line: 0, character: 0 },
            end: { line: 3, character: 1 },
          },
        },
      }]
    )
  end

  def test_selecting_multiline_method_invocation
    fixture = <<~RUBY
      foo.invocation(
        a: 1,
        b: 2,
      )
    RUBY

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 2 },
          end: { line: 1, character: 4 },
        },
        # The fact that this doesn't have more parents feels wrong to me...
        parent: {
          range: {
            start: { line: 0, character: 0 },
            end: { line: 3, character: 1 },
          },
        },
      }]
    )
  end

  def test_selecting_nested_multiline_method_invocation
    fixture = <<~RUBY
      foo.invocation(
        another_invocation(
          1,
          2
        )
      )
    RUBY

    assert_ranges(
      fixture,
      [{ line: 2, character: 4 }],
      [{
        range: {
          start: { line: 2, character: 4 },
          end: { line: 2, character: 5 },
        },
        parent: {
          range: {
            start: { line: 1, character: 2 },
            end: { line: 4, character: 3 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 5, character: 1 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_nested_multiline_method_invocation_no_parenthesis
    fixture = <<~RUBY
      foo.invocation(
        another_invocation 1,
          2
      )
    RUBY

    assert_ranges(
      fixture,
      [{ line: 2, character: 4 }],
      [{
        range: {
          start: { line: 2, character: 4 },
          end: { line: 2, character: 5 },
        },
        parent: {
          range: {
            start: { line: 1, character: 2 },
            end: { line: 2, character: 5 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 3, character: 1 },
            },
          },
        },
      }]
    )
  end

  def test_selecting_heredoc
    fixture = <<~RUBY
      <<-HEREDOC
        some text
      HEREDOC
    RUBY

    assert_ranges(
      fixture,
      [{ line: 1, character: 2 }],
      [{
        range: {
          start: { line: 1, character: 0 },
          end: { line: 1, character: 12 },
        },
        parent: {
          range: {
            start: { line: 0, character: 0 },
            end: { line: 2, character: 0 },
          },
        },
      }]
    )
  end

  def test_selecting_multiline_if_else_statements
    fixture = <<~RUBY
      if true
        puts "Yes!"
      elsif false
        puts "Maybe?"
      else
        puts "No"
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 5, character: 2 }],
      [{
        range: {
          start: { line: 5, character: 2 },
          end: { line: 5, character: 6 },
        },
        parent: {
          range: {
            start: { line: 5, character: 2 },
            end: { line: 5, character: 11 },
          },
          parent: {
            range: {
              start: { line: 4, character: 0 },
              end: { line: 6, character: 3 },
            },
            parent: {
              range: {
                start: { line: 2, character: 0 },
                end: { line: 6, character: 3 },
              },
              parent: {
                range: {
                  start: { line: 0, character: 0 },
                  end: { line: 6, character: 3 },
                },
              },
            },
          },
        },
      }]
    )
  end

  def test_selecting_multiline_if_else_empty_statements
    fixture = <<~RUBY
      if true
      elsif false
      else
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 2, character: 0 }],
      [{
        range: {
          start: { line: 2, character: 0 },
          end: { line: 2, character: 4 },
        },
        parent: {
          range: {
            start: { line: 2, character: 0 },
            end: { line: 3, character: 3 },
          },
          parent: {
            range: {
              start: { line: 1, character: 0 },
              end: { line: 3, character: 3 },
            },
            parent: {
              range: {
                start: { line: 0, character: 0 },
                end: { line: 3, character: 3 },
              },
            },
          },
        },
      }]
    )
  end

  def test_selecting_case
    fixture = <<~RUBY
      case node
      when CaseNode
        puts "case"
      else
        puts "else"
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 2, character: 2 }],
      [{
        range: {
          start: { line: 2, character: 2 },
          end: { line: 2, character: 6 },
        },
        parent: {
          range: {
            start: { line: 2, character: 2 },
            end: { line: 2, character: 13 },
          },
          parent: {
            range: {
              start: { line: 1, character: 0 },
              end: { line: 5, character: 3 },
            },
            parent: {
              range: {
                start: { line: 0, character: 0 },
                end: { line: 5, character: 3 },
              },
            },
          },
        },
      }]
    )
  end

  def test_selecting_rescue_and_ensure
    fixture = <<~RUBY
      begin
        puts "begin"
      rescue StandardError => e
        puts "stderror"
      rescue Exception => e
        puts "exception"
      ensure
        puts "ensure"
      end
    RUBY

    # Test rescue
    assert_ranges(
      fixture,
      [{ line: 5, character: 2 }],
      [{
        range: {
          start: { line: 5, character: 2 },
          end: { line: 5, character: 6 },
        },
        parent: {
          range: {
            start: { line: 5, character: 2 },
            end: { line: 5, character: 18 },
          },
          parent: {
            range: {
              start: { line: 4, character: 0 },
              end: { line: 6, character: 0 },
            },
            parent: {
              range: {
                start: { line: 2, character: 0 },
                end: { line: 6, character: 0 },
              },
              parent: {
                range: {
                  start: { line: 0, character: 0 },
                  end: { line: 8, character: 3 },
                },
              },
            },
          },
        },
      }]
    )

    # Test ensure
    assert_ranges(
      fixture,
      [{ line: 7, character: 2 }],
      [{
        range: {
          start: { line: 7, character: 2 },
          end: { line: 7, character: 6 },
        },
        parent: {
          range: {
            start: { line: 7, character: 2 },
            end: { line: 7, character: 15 },
          },
          parent: {
            range: {
              start: { line: 6, character: 0 },
              end: { line: 8, character: 3 },
            },
            parent: {
              range: {
                start: { line: 0, character: 0 },
                end: { line: 8, character: 3 },
              },
            },
          },
        },
      }]
    )
  end

  def test_selecting_multiline_comments
    # TODO: implement
    skip
  end

  def test_selecting_multiline_strings
    fixture = <<~RUBY
      "foo" \\
      "bar" \\
      "baz"
    RUBY

    assert_ranges(
      fixture,
      [{ line: 1, character: 3 }],
      [{
        range: {
          start: { line: 1, character: 1 },
          end: { line: 1, character: 4 },
        },
        parent: {
          range: {
            start: { line: 1, character: 0 },
            end: { line: 1, character: 5 },
          },
          parent: {
            range: {
              start: { line: 0, character: 0 },
              end: { line: 1, character: 5 },
            },
            parent: {
              range: {
                start: { line: 0, character: 0 },
                end: { line: 2, character: 5 },
              },
            },
          },
        },
      }]
    )
  end

  def test_selecting_pattern_matching
    fixture = <<~RUBY
      case foo
      in { a: 1 }
        puts "a"
      else
        puts "nothing"
      end
    RUBY

    assert_ranges(
      fixture,
      [{ line: 1, character: 5 }],
      [{
        range: {
          start: { line: 1, character: 5 },
          end: { line: 1, character: 7 },
        },
        parent: {
          range: {
            start: { line: 1, character: 3 },
            end: { line: 1, character: 11 },
          },
          parent: {
            range: {
              start: { line: 1, character: 0 },
              end: { line: 5, character: 3 },
            },
            parent: {
              range: {
                start: { line: 0, character: 0 },
                end: { line: 5, character: 3 },
              },
            },
          },
        },
      }]
    )

    assert_ranges(
      fixture,
      [{ line: 2, character: 2 }],
      [{
        range: {
          start: { line: 2, character: 2 },
          end: { line: 2, character: 6 },
        },
        parent: {
          range: {
            start: { line: 2, character: 2 },
            end: { line: 2, character: 10 },
          },
          parent: {
            range: {
              start: { line: 1, character: 0 },
              end: { line: 5, character: 3 },
            },
            parent: {
              range: {
                start: { line: 0, character: 0 },
                end: { line: 5, character: 3 },
              },
            },
          },
        },
      }]
    )
  end

  private

  def assert_ranges(source, positions, expected_ranges)
    document = RubyLsp::Document.new(source)
    actual = RubyLsp::Requests::SelectionRanges.new(document).run
    filtered = positions.map { |position| actual.find { |range| range.cover?(position) } }

    assert_equal(expected_ranges, JSON.parse(filtered.to_json, symbolize_names: true))
  end
end
