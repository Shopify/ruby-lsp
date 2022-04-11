# frozen_string_literal: true

require "test_helper"

class DocumentSymbolsTest < Minitest::Test
  def test_attr_accessor
    symbols = [
      {
        name: "a",
        kind: :field,
        range: "0:12-0:14",
        selectionRange: "0:13-0:14",
      },
      {
        name: "b",
        kind: :field,
        range: "1:12-1:14",
        selectionRange: "1:13-1:14",
      },
      {
        name: "c",
        kind: :field,
        range: "1:16-1:18",
        selectionRange: "1:17-1:18",
      },
      {
        name: "d",
        kind: :field,
        range: "2:14-2:16",
        selectionRange: "2:15-2:16",
      },
    ]
    assert_symbols(<<~RUBY, symbols)
      attr_reader :a
      attr_writer :b, :c
      attr_accessor :d
    RUBY
  end

  def test_class_declaration
    symbols = [
      {
        name: "Foo",
        kind: :class,
        range: "0:0-2:3",
        selectionRange: "0:6-0:9",
        children: [
          {
            name: "Bar",
            kind: :class,
            range: "1:2-1:16",
            selectionRange: "1:8-1:11",
          },
        ],
      },
    ]
    assert_symbols(<<~RUBY, symbols)
      class Foo
        class Bar; end
      end
    RUBY
  end

  def test_constant
    symbols = [
      {
        name: "C1",
        kind: :constant,
        range: "0:0-0:2",
        selectionRange: "0:0-0:2",
      },
      {
        name: "C2",
        kind: :constant,
        range: "1:0-1:4",
        selectionRange: "1:2-1:4",
      },
      {
        name: "C3",
        kind: :constant,
        range: "2:0-2:7",
        selectionRange: "2:5-2:7",
      },
      {
        name: "C4",
        kind: :constant,
        range: "3:0-3:9",
        selectionRange: "3:7-3:9",
      },
    ]
    assert_symbols(<<~RUBY, symbols)
      C1 = 42
      ::C2 = 42
      Foo::C3 = 42
      ::Foo::C4 = 42
    RUBY
  end

  def test_i_vars
    symbols = [
      {
        name: "@a",
        kind: :variable,
        range: "0:0-0:2",
        selectionRange: "0:0-0:2",
      },
      {
        name: "@aa",
        kind: :variable,
        range: "1:0-1:3",
        selectionRange: "1:0-1:3",
      },
      {
        name: "Foo",
        kind: :class,
        range: "3:0-11:3",
        selectionRange: "3:6-3:9",
        children: [
          {
            name: "@b",
            kind: :variable,
            range: "4:2-4:4",
            selectionRange: "4:2-4:4",
          },
          {
            name: "@bb",
            kind: :variable,
            range: "5:2-5:5",
            selectionRange: "5:2-5:5",
          },
          {
            name: "initialize",
            kind: :constructor,
            range: "7:2-10:5",
            selectionRange: "7:6-7:16",
            children: [
              {
                name: "@c",
                kind: :variable,
                range: "8:4-8:6",
                selectionRange: "8:4-8:6",
              },
              {
                name: "@cc",
                kind: :variable,
                range: "9:4-9:7",
                selectionRange: "9:4-9:7",
              },
            ],
          },
        ],
      },
    ]
    assert_symbols(<<~RUBY, symbols)
      @a = 42
      @aa = 42

      class Foo
        @b = 42
        @bb = 42

        def initialize
          @c = 42
          @cc = 42
        end
      end
    RUBY
  end

  def test_method
    symbols = [
      {
        name: "foo",
        kind: :method,
        range: "0:0-0:12",
        selectionRange: "0:4-0:7",
      },
      {
        name: "initialize",
        kind: :constructor,
        range: "1:0-1:19",
        selectionRange: "1:4-1:14",
      },
      {
        name: "self.bar",
        kind: :method,
        range: "2:0-2:17",
        selectionRange: "2:9-2:12",
      },
    ]
    assert_symbols(<<~RUBY, symbols)
      def foo; end
      def initialize; end
      def self.bar; end
    RUBY
  end

  def test_method_endless
    skip if RUBY_VERSION < "3.1.0"

    symbols = [
      {
        name: "baz",
        kind: :method,
        range: "0:0-0:13",
        selectionRange: "0:4-0:7",
      },
    ]
    assert_symbols(<<~RUBY, symbols)
      def baz = 10
    RUBY
  end

  def test_module_declaration
    symbols = [
      {
        name: "Foo",
        kind: :module,
        range: "0:0-2:3",
        selectionRange: "0:7-0:10",
        children: [
          {
            name: "Bar",
            kind: :module,
            range: "1:2-1:17",
            selectionRange: "1:9-1:12",
          },
        ],
      },
    ]
    assert_symbols(<<~RUBY, symbols)
      module Foo
        module Bar; end
      end
    RUBY
  end

  private

  def assert_symbols(source, expected_symbols, print_result: false)
    parsed_tree = RubyLsp::Store::ParsedTree.new(source)
    actual = RubyLsp::Requests::DocumentSymbol.run(parsed_tree)
    actual_json = JSON.parse(actual.to_json, symbolize_names: true)
    simplified_symbol = simplified_symbols(actual_json)

    # Used only for debugging, pass `print_result: true` to see the simplified result
    puts JSON.pretty_generate(simplified_symbol) if print_result

    assert_equal(expected_symbols, simplified_symbol)
  end

  def simplified_symbols(symbols)
    symbols.map do |symbol|
      child = {
        name: symbol[:name],
        kind: RubyLsp::Requests::DocumentSymbol::SYMBOL_KIND.key(symbol[:kind]),
        range: simplified_loc(symbol[:range]),
        selectionRange: simplified_loc(symbol[:selectionRange]),

      }
      child[:children] = simplified_symbols(symbol[:children]) unless symbol[:children].empty?
      child
    end
  end

  def simplified_loc(loc)
    "#{loc[:start][:line]}:#{loc[:start][:character]}-#{loc[:end][:line]}:#{loc[:end][:character]}"
  end
end
