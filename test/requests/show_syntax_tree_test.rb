# typed: true
# frozen_string_literal: true

require "test_helper"

class ShowSyntaxTreeTest < Minitest::Test
  def setup
    @message_queue = Thread::Queue.new
  end

  def teardown
    @message_queue.close
  end

  def test_returns_partial_tree_if_document_has_syntax_error
    store = RubyLsp::Store.new
    store.set(uri: URI("file:///fake.rb"), source: "foo do", version: 1)
    response = RubyLsp::Executor.new(store, @message_queue).execute({
      method: "rubyLsp/textDocument/showSyntaxTree",
      params: { textDocument: { uri: "file:///fake.rb" } },
    }).response

    assert_equal(<<~AST, response[:ast])
      @ ProgramNode (location: (1,0)-(1,6))
      ├── locals: []
      └── statements:
          @ StatementsNode (location: (1,0)-(1,6))
          └── body: (length: 1)
              └── @ CallNode (location: (1,0)-(1,6))
                  ├── flags: ∅
                  ├── receiver: ∅
                  ├── call_operator_loc: ∅
                  ├── name: :foo
                  ├── message_loc: (1,0)-(1,3) = "foo"
                  ├── opening_loc: ∅
                  ├── arguments: ∅
                  ├── closing_loc: ∅
                  └── block:
                      @ BlockNode (location: (1,4)-(1,6))
                      ├── locals: []
                      ├── locals_body_index: 0
                      ├── parameters: ∅
                      ├── body:
                      │   @ StatementsNode (location: (1,4)-(1,6))
                      │   └── body: (length: 1)
                      │       └── @ MissingNode (location: (1,4)-(1,6))
                      ├── opening_loc: (1,4)-(1,6) = "do"
                      └── closing_loc: (1,6)-(1,6) = ""
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
      @ ProgramNode (location: (1,0)-(1,9))
      ├── locals: [:foo]
      └── statements:
          @ StatementsNode (location: (1,0)-(1,9))
          └── body: (length: 1)
              └── @ LocalVariableWriteNode (location: (1,0)-(1,9))
                  ├── name: :foo
                  ├── depth: 0
                  ├── name_loc: (1,0)-(1,3) = "foo"
                  ├── value:
                  │   @ IntegerNode (location: (1,6)-(1,9))
                  │   └── flags: decimal
                  └── operator_loc: (1,4)-(1,5) = "="
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
      @ LocalVariableWriteNode (location: (1,0)-(1,9))
      ├── name: :foo
      ├── depth: 0
      ├── name_loc: (1,0)-(1,3) = "foo"
      ├── value:
      │   @ IntegerNode (location: (1,6)-(1,9))
      │   └── flags: decimal
      └── operator_loc: (1,4)-(1,5) = "="

      @ LocalVariableWriteNode (location: (2,0)-(2,9))
      ├── name: :bar
      ├── depth: 0
      ├── name_loc: (2,0)-(2,3) = "bar"
      ├── value:
      │   @ IntegerNode (location: (2,6)-(2,9))
      │   └── flags: decimal
      └── operator_loc: (2,4)-(2,5) = "="
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
