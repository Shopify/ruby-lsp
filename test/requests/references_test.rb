# typed: true
# frozen_string_literal: true

require "test_helper"

class ReferencesTest < Minitest::Test
  def test_finds_constant_references
    source = <<~RUBY
      class Foo
      end

      Foo
      Foo.new
    RUBY

    refs = find_references(source, { line: 3, character: 0 })
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 3)
    assert_includes(ref_lines, 4)
  end

  def test_finds_constant_references_with_include_declaration
    source = <<~RUBY
      class Foo
      end

      Foo
    RUBY

    refs = find_references(source, { line: 3, character: 0 }, include_declarations: true)
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 0)
    assert_includes(ref_lines, 3)
  end

  def test_finds_method_references_for_call_node
    source = <<~RUBY
      class Foo
        def bar
          baz
        end

        def baz
        end
      end

      Foo.new.baz
    RUBY

    # Cursor on the `baz` call inside the bar method (line 2, character 4)
    refs = find_references(source, { line: 2, character: 4 })
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 2)
    assert_includes(ref_lines, 9)
  end

  def test_finds_method_references_with_include_declaration
    source = <<~RUBY
      class Foo
        def bar
        end
      end

      Foo.new.bar
    RUBY

    # Cursor on the `bar` call (line 5, character 8)
    refs = find_references(source, { line: 5, character: 8 }, include_declarations: true)
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 1) # definition
    assert_includes(ref_lines, 5) # reference
  end

  AMBIGUOUS_BAR_SOURCE = <<~RUBY
    class Foo
      def self.bar
      end
    end

    class Qux
      def bar
      end
    end

    class Other
      def self.bar
      end
    end

    it = Qux.new
    it.bar

    Foo.bar
    Other.bar
  RUBY

  def test_filters_method_references_when_call_site_receiver_is_a_known_constant
    refs = find_references(AMBIGUOUS_BAR_SOURCE, { line: 18, character: 4 }, include_declarations: true)
    ref_lines = refs.map { |r| r.range.start.line }

    assert_includes(ref_lines, 1) # def self.bar declaration
    refute_includes(ref_lines, 6) # def bar (Qux) must not appear
    refute_includes(ref_lines, 11) # def self.bar (Other) must not appear
    assert_includes(ref_lines, 16) # it.bar included because receiver is unresolved
    assert_includes(ref_lines, 18) # Foo.bar call site
    refute_includes(ref_lines, 19) # Other.bar call site is filtered out by its resolved receiver
  end

  def test_falls_back_to_all_candidates_when_call_site_receiver_is_unresolvable
    refs = find_references(AMBIGUOUS_BAR_SOURCE, { line: 16, character: 3 }, include_declarations: true)
    ref_lines = refs.map { |r| r.range.start.line }

    assert_includes(ref_lines, 1) # Foo.bar declaration
    assert_includes(ref_lines, 6) # Qux#bar declaration
    assert_includes(ref_lines, 11) # Other.bar declaration
    assert_includes(ref_lines, 16) # it.bar call site
    assert_includes(ref_lines, 18) # Foo.bar call site
    assert_includes(ref_lines, 19) # Other.bar call site
  end

  def test_method_references_match_through_superclass_chain
    source = <<~RUBY
      class Parent
        def self.bar
        end
      end

      class Child < Parent
      end

      Parent.bar
      Child.bar
    RUBY

    refs = find_references(source, { line: 1, character: 11 }, include_declarations: true)
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 1) # Parent.bar declaration
    assert_includes(ref_lines, 8) # Parent.bar call site
    assert_includes(ref_lines, 9) # Child.bar call site (matched through Child::<Child>'s ancestors)
  end

  def test_finds_references_from_def_node
    source = <<~RUBY
      class Foo
        def bar
        end
      end

      Foo.new.bar
    RUBY

    # Cursor on the `bar` in `def bar` (line 1, character 6)
    refs = find_references(source, { line: 1, character: 6 })
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 5) # the Foo.new.bar call
  end

  def test_finds_references_from_def_node_with_include_declaration
    source = <<~RUBY
      class Foo
        def bar
        end
      end

      Foo.new.bar
    RUBY

    refs = find_references(source, { line: 1, character: 6 }, include_declarations: true)
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 1) # definition
    assert_includes(ref_lines, 5) # call site
  end

  def test_finds_references_for_singleton_method_def
    source = <<~RUBY
      class Foo
        def self.bar
        end
      end

      Foo.bar
    RUBY

    # Cursor on `bar` in `def self.bar` (line 1, character 11)
    refs = find_references(source, { line: 1, character: 11 })
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 5) # Foo.bar call
  end

  def test_singleton_method_def_resolves_to_singleton_declaration_not_instance
    source = <<~RUBY
      class Foo
        def self.bar
        end

        def bar
        end
      end

      Foo.bar
    RUBY

    refs = find_references(source, { line: 1, character: 11 }, include_declarations: true)
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 1)
    assert_includes(ref_lines, 8)
    refute_includes(ref_lines, 4)
  end

  def test_instance_variables_return_empty
    source = <<~RUBY
      class Foo
        def initialize
          @name = "test"
        end

        def name
          @name
        end
      end
    RUBY

    # Placeholder: Rubydex's InstanceVariable#references currently returns an empty array
    refs = find_references(source, { line: 2, character: 5 })
    assert_empty(refs)
  end

  def test_instance_variable_include_declarations
    source = <<~RUBY
      class Foo
        def initialize
          @name = "test"
        end

        def name
          @name
        end
      end
    RUBY

    # Even though references are empty, the declaration should be included when requested
    refs = find_references(source, { line: 2, character: 5 }, include_declarations: true)
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 2)
  end

  def test_class_variables_return_empty
    source = <<~RUBY
      class Foo
        @@count = 0

        def increment
          @@count += 1
        end

        def count
          @@count
        end
      end
    RUBY

    # Placeholder: Rubydex's ClassVariable#references currently returns an empty array
    refs = find_references(source, { line: 1, character: 2 })
    assert_empty(refs)
  end

  def test_class_variable_include_declarations
    source = <<~RUBY
      class Foo
        @@count = 0
      end
    RUBY

    refs = find_references(source, { line: 1, character: 2 }, include_declarations: true)
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 1)
  end

  def test_global_variables_return_empty
    source = <<~RUBY
      $global = "value"
      puts $global
    RUBY

    # Placeholder: Rubydex's GlobalVariable#references currently returns an empty array
    refs = find_references(source, { line: 0, character: 0 })
    assert_empty(refs)
  end

  def test_global_variable_include_declarations
    source = <<~RUBY
      $global = "value"
    RUBY

    refs = find_references(source, { line: 0, character: 0 }, include_declarations: true)
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 0)
  end

  def test_finds_constant_path_references
    source = <<~RUBY
      module Foo
        class Bar
        end
      end

      Foo::Bar
    RUBY

    # Cursor on `Bar` in `Foo::Bar` (line 5, character 5)
    refs = find_references(source, { line: 5, character: 5 })
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 5)
  end

  def test_finds_references_for_constant_write_node
    source = <<~RUBY
      FOO = 1
      puts FOO
    RUBY

    refs = find_references(source, { line: 0, character: 0 })
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 1)
  end

  def test_finds_references_for_constant_and_write_node
    source = <<~RUBY
      FOO = 1
      FOO &&= 2
      puts FOO
    RUBY

    refs = find_references(source, { line: 1, character: 0 })
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 1)
    assert_includes(ref_lines, 2)
  end

  def test_finds_references_for_constant_or_write_node
    source = <<~RUBY
      FOO ||= 1
      puts FOO
    RUBY

    refs = find_references(source, { line: 0, character: 0 })
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 1)
  end

  def test_finds_references_for_constant_operator_write_node
    source = <<~RUBY
      FOO = 1
      FOO += 2
      puts FOO
    RUBY

    refs = find_references(source, { line: 1, character: 0 })
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 1)
    assert_includes(ref_lines, 2)
  end

  def test_finds_references_for_constant_path_write_node
    source = <<~RUBY
      module Foo
      end
      Foo::BAR = 1
      puts Foo::BAR
    RUBY

    refs = find_references(source, { line: 2, character: 6 })
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 3)
  end

  def test_cursor_on_assignment_operator_returns_no_references
    source = <<~RUBY
      module Foo
      end
      Foo::BAR = 1
      puts Foo::BAR
    RUBY

    refs = find_references(source, { line: 2, character: 9 })
    assert_empty(refs)
  end

  def test_finds_references_for_call_operator_write_node
    source = <<~RUBY
      class Foo
        def bar
          0
        end

        def bar=(value)
        end
      end

      f = Foo.new
      f.bar += 1
      f.bar
    RUBY

    # Cursor on `bar` in `f.bar += 1`
    refs = find_references(source, { line: 10, character: 2 })
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 10)
    assert_includes(ref_lines, 11)
  end

  def test_references_filter_out_rubydex_builtin_uris
    source = <<~RUBY
      class Object
      end
    RUBY

    refs = find_references(source, { line: 0, character: 6 }, include_declarations: true)

    refute_empty(refs)
    assert(refs.any? { |ref| URI(ref.uri).scheme == "file" }, "Expected at least one file: URI ref")

    refs.each do |ref|
      refute_equal("rubydex", URI(ref.uri).scheme, "rubydex: URIs must not leak to the LSP client")
    end
  end

  def test_returns_empty_for_no_target
    refs = find_references("x = 1", { line: 0, character: 0 })
    assert_empty(refs)
  end

  def test_references_in_unsaved_files_are_included
    source = <<~RUBY
      class MyClass
      end

      MyClass
    RUBY

    untitled_uri = URI("untitled:Untitled-1")
    untitled_source = "MyClass\n"

    refs = find_references(source, { line: 3, character: 0 }) do |graph|
      graph.index_source(untitled_uri.to_s, untitled_source, "ruby")
    end

    assert_includes(refs.map(&:uri), untitled_uri.to_s)
  end

  def test_reference_ranges_are_utf8_code_units_when_negotiated
    source = <<~RUBY
      class Foo; end
      "🙂"; Foo
    RUBY

    refs = find_references(source, { line: 0, character: 6 }, encoding: :utf8)
    on_line_one = refs.find { |r| r.range.start.line == 1 } #: as !nil
    # UTF-8 bytes: " (1) + 🙂 (4) + " (1) + ; (1) + space (1) = 8 before F
    assert_equal(8, on_line_one.range.start.character)
    assert_equal(11, on_line_one.range.end.character)
  end

  def test_reference_ranges_are_utf16_code_units_when_negotiated
    source = <<~RUBY
      class Foo; end
      "🙂"; Foo
    RUBY

    refs = find_references(source, { line: 0, character: 6 }, encoding: :utf16)
    on_line_one = refs.find { |r| r.range.start.line == 1 } #: as !nil
    # UTF-16 code units: " (1) + 🙂 (2) + " (1) + ; (1) + space (1) = 6 before F
    assert_equal(6, on_line_one.range.start.character)
    assert_equal(9, on_line_one.range.end.character)
  end

  def test_reference_ranges_are_utf32_code_units_when_negotiated
    source = <<~RUBY
      class Foo; end
      "🙂"; Foo
    RUBY

    refs = find_references(source, { line: 0, character: 6 }, encoding: :utf32)
    on_line_one = refs.find { |r| r.range.start.line == 1 } #: as !nil
    # UTF-32 code units: " (1) + 🙂 (1) + " (1) + ; (1) + space (1) = 5 before F
    assert_equal(5, on_line_one.range.start.character)
    assert_equal(8, on_line_one.range.end.character)
  end

  def test_unresolved_method_call_surfaces_all_candidate_declarations
    source = <<~RUBY
      class Foo
        def bar
        end
      end

      class Baz
        def bar
        end
      end

      unknown_var.bar
    RUBY

    # Cursor on `bar` in `unknown_var.bar` (line 10, character 12). `unknown_var` can't be
    # resolved, so every method named `bar` is a candidate. The user needs to see each one to
    # decide which declaration the call actually refers to — we must not drop any candidate
    # just because they share an unqualified name.
    refs = find_references(source, { line: 10, character: 12 }, include_declarations: true)
    ref_lines = refs.map { |r| r.range.start.line }
    assert_includes(ref_lines, 1)
    assert_includes(ref_lines, 6)
    assert_includes(ref_lines, 10)
  end

  def test_cursor_on_constant_write_value_returns_no_references
    source = <<~RUBY
      FOO = 1
      puts FOO
    RUBY

    # Cursor on `1` in `FOO = 1` (line 0, character 6). The cursor is not on the constant name,
    # so we must return no references.
    refs = find_references(source, { line: 0, character: 6 })
    assert_empty(refs)
  end

  def test_cursor_on_constant_and_write_operator_returns_no_references
    source = <<~RUBY
      FOO = 1
      FOO &&= 2
    RUBY

    # Cursor on `&&=` in `FOO &&= 2` (line 1, character 5). Not on the constant name.
    refs = find_references(source, { line: 1, character: 5 })
    assert_empty(refs)
  end

  def test_cursor_on_constant_operator_write_operator_returns_no_references
    source = <<~RUBY
      FOO = 1
      FOO += 2
    RUBY

    # Cursor on `+=` in `FOO += 2` (line 1, character 4). Not on the constant name.
    refs = find_references(source, { line: 1, character: 4 })
    assert_empty(refs)
  end

  def test_cursor_on_instance_variable_write_value_returns_no_references
    source = <<~RUBY
      class Foo
        def initialize
          @name = "test"
        end

        def name
          @name
        end
      end
    RUBY

    # Cursor on `"test"` in `@name = "test"` (line 2, character 12). Not on the variable name.
    refs = find_references(source, { line: 2, character: 12 }, include_declarations: true)
    assert_empty(refs)
  end

  def test_cursor_on_class_variable_write_value_returns_no_references
    source = <<~RUBY
      class Foo
        @@count = 0
      end
    RUBY

    # Cursor on `0` in `@@count = 0` (line 1, character 12). Not on the variable name.
    refs = find_references(source, { line: 1, character: 12 }, include_declarations: true)
    assert_empty(refs)
  end

  def test_cursor_on_global_variable_write_value_returns_no_references
    source = <<~RUBY
      $global = "value"
    RUBY

    # Cursor on `"value"` in `$global = "value"` (line 0, character 11). Not on the variable name.
    refs = find_references(source, { line: 0, character: 11 }, include_declarations: true)
    assert_empty(refs)
  end

  def test_cursor_on_call_argument_returns_no_references
    source = <<~RUBY
      class Foo
        def bar(arg)
        end
      end

      Foo.new.bar(42)
    RUBY

    # Cursor on `42` (line 5, character 12). Not on the method name, so no references.
    refs = find_references(source, { line: 5, character: 12 })
    assert_empty(refs)
  end

  def test_cursor_on_call_operator_write_operator_returns_no_references
    source = <<~RUBY
      class Foo
        def bar
          0
        end

        def bar=(value)
        end
      end

      f = Foo.new
      f.bar += 1
    RUBY

    # Cursor on `+=` in `f.bar += 1` (line 10, character 6). Not on the method name.
    refs = find_references(source, { line: 10, character: 6 })
    assert_empty(refs)
  end

  def test_cursor_on_def_node_body_returns_no_references
    source = <<~RUBY
      class Foo
        def bar
          42
        end
      end

      Foo.new.bar
    RUBY

    # Cursor on `42` inside the method body (line 2, character 4). Not on the method name.
    refs = find_references(source, { line: 2, character: 4 })
    assert_empty(refs)
  end

  def test_does_not_include_declarations_by_default
    source = <<~RUBY
      class Foo
      end

      Foo
    RUBY

    refs = find_references(source, { line: 3, character: 0 })
    ref_lines = refs.map { |r| r.range.start.line }
    refute_includes(ref_lines, 0)
    assert_includes(ref_lines, 3)
  end

  private

  #: (String source, Hash[Symbol, Integer] position, ?include_declarations: bool, ?encoding: Symbol) ?{ (Rubydex::Graph) -> void } -> Array[RubyLsp::Interface::Location]
  def find_references(source, position, include_declarations: false, encoding: :utf8, &block)
    uri = URI::Generic.from_path(path: "/fake/path/test.rb")
    global_state = RubyLsp::GlobalState.new
    ruby_encoding = case encoding
    when :utf8 then Encoding::UTF_8
    when :utf16 then Encoding::UTF_16LE
    when :utf32 then Encoding::UTF_32LE
    end
    global_state.instance_variable_set(:@encoding, ruby_encoding)
    graph = global_state.graph
    graph.encoding = encoding.to_s

    graph.index_source(uri.to_s, source, "ruby")
    block&.call(graph)
    graph.resolve

    store = RubyLsp::Store.new(global_state)
    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: uri,
      global_state: global_state,
    )

    RubyLsp::Requests::References.new(
      global_state,
      store,
      document,
      {
        position: position,
        context: { includeDeclaration: include_declarations },
      },
    ).perform
  end
end
