# frozen_string_literal: true

require "test_helper"

class DocumentSymbolsTest < Minitest::Test
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
