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
      ProgramNode(0...6)(
        [],
        StatementsNode(0...6)(
          [CallNode(0...6)(
             nil,
             nil,
             (0...3),
             nil,
             nil,
             nil,
             BlockNode(4...6)(
               [],
               nil,
               StatementsNode(4...6)([MissingNode(4...6)()]),
               (4...6),
               (6...6)
             ),
             0,
             "foo"
           )]
        )
      )
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
      ProgramNode(0...9)(
        [:foo],
        StatementsNode(0...9)(
          [LocalVariableWriteNode(0...9)(
             :foo,
             0,
             IntegerNode(6...9)(),
             (0...3),
             (4...5)
           )]
        )
      )
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
      LocalVariableWriteNode(0...9)(:foo, 0, IntegerNode(6...9)(), (0...3), (4...5))

      LocalVariableWriteNode(10...19)(
        :bar,
        0,
        IntegerNode(16...19)(),
        (10...13),
        (14...15)
      )
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
