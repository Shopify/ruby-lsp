# typed: true
# frozen_string_literal: true

require "test_helper"

class ShowSyntaxTreeTest < Minitest::Test
  def setup
    @message_queue = Thread::Queue.new
  end

  def teardown
    @message_queue.close
    super
  end

  def test_returns_partial_tree_if_document_has_syntax_error
    store = RubyLsp::Store.new
    store.set(uri: URI("file:///fake.rb"), source: "foo do", version: 1)
    response = RubyLsp::Executor.new(store, @message_queue).execute({
      method: "rubyLsp/textDocument/showSyntaxTree",
      params: { textDocument: { uri: "file:///fake.rb" } },
    }).response

    assert_equal(<<~AST, response[:ast])
      @ ProgramNode (location: (0...6))
      ├── locals: []
      └── statements:
          @ StatementsNode (location: (0...6))
          └── body: (length: 1)
              └── @ CallNode (location: (0...6))
                  ├── receiver: ∅
                  ├── call_operator_loc: ∅
                  ├── message_loc: (0...3) = "foo"
                  ├── opening_loc: ∅
                  ├── arguments: ∅
                  ├── closing_loc: ∅
                  ├── block:
                  │   @ BlockNode (location: (4...6))
                  │   ├── locals: []
                  │   ├── parameters: ∅
                  │   ├── body:
                  │   │   @ StatementsNode (location: (4...6))
                  │   │   └── body: (length: 1)
                  │   │       └── @ MissingNode (location: (4...6))
                  │   ├── opening_loc: (4...6) = "do"
                  │   └── closing_loc: (6...6) = ""
                  ├── flags: ∅
                  └── name: "foo"
    AST
  end

  def test_returns_ast_if_document_is_parsed
    store = RubyLsp::Store.new
    store.set(uri: URI("file:///fake.rb"), source: "foo = 123", version: 1)
    document = store.get(URI("file:///fake.rb"))
    document.parse

    response = RubyLsp::Executor.new(store, @message_queue).execute({
      method: "rubyLsp/textDocument/showSyntaxTree",
      params: { textDocument: { uri: "file:///fake.rb" } },
    }).response

    assert_equal(<<~AST, response[:ast])
      @ ProgramNode (location: (0...9))
      ├── locals: [:foo]
      └── statements:
          @ StatementsNode (location: (0...9))
          └── body: (length: 1)
              └── @ LocalVariableWriteNode (location: (0...9))
                  ├── name: :foo
                  ├── depth: 0
                  ├── name_loc: (0...3) = "foo"
                  ├── value:
                  │   @ IntegerNode (location: (6...9))
                  │   └── flags: decimal
                  └── operator_loc: (4...5) = "="
    AST
  end

  def test_returns_ast_for_a_selection
    uri = URI("file:///fake.rb")
    store = RubyLsp::Store.new
    store.set(uri: uri, source: <<~RUBY, version: 1)
      foo = 123
      bar = 456
      hello = 123
    RUBY
    document = store.get(uri)
    document.parse

    response = RubyLsp::Executor.new(store, @message_queue).execute({
      method: "rubyLsp/textDocument/showSyntaxTree",
      params: {
        textDocument: { uri: "file:///fake.rb" },
        range: { start: { line: 0, character: 0 }, end: { line: 1, character: 9 } },
      },
    }).response

    assert_equal(<<~AST, response[:ast])
      @ LocalVariableWriteNode (location: (0...9))
      ├── name: :foo
      ├── depth: 0
      ├── name_loc: (0...3) = "foo"
      ├── value:
      │   @ IntegerNode (location: (6...9))
      │   └── flags: decimal
      └── operator_loc: (4...5) = "="

      @ LocalVariableWriteNode (location: (10...19))
      ├── name: :bar
      ├── depth: 0
      ├── name_loc: (10...13) = "bar"
      ├── value:
      │   @ IntegerNode (location: (16...19))
      │   └── flags: decimal
      └── operator_loc: (14...15) = "="
    AST

    # We execute twice just to make sure we do not mutate by mistake.

    response = RubyLsp::Executor.new(store, @message_queue).execute({
      method: "rubyLsp/textDocument/showSyntaxTree",
      params: {
        textDocument: { uri: "file:///fake.rb" },
        range: { start: { line: 1, character: 0 }, end: { line: 1, character: 9 } },
      },
    }).response
    refute_empty(response[:ast])
  end
end
