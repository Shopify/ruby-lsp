# typed: true
# frozen_string_literal: true

require "test_helper"

class ShowSyntaxTreeTest < Minitest::Test
  def test_returns_partial_tree_if_document_has_syntax_error
    with_server("foo do") do |server, uri|
      server.process_message(
        id: 1,
        method: "rubyLsp/textDocument/showSyntaxTree",
        params: { textDocument: { uri: uri } },
      )

      assert_equal(<<~AST, server.pop_response.response[:ast])
        @ ProgramNode (location: (1,0)-(1,6))
        ├── flags: ∅
        ├── locals: []
        └── statements:
            @ StatementsNode (location: (1,0)-(1,6))
            ├── flags: ∅
            └── body: (length: 1)
                └── @ CallNode (location: (1,0)-(1,6))
                    ├── flags: newline, ignore_visibility
                    ├── receiver: ∅
                    ├── call_operator_loc: ∅
                    ├── name: :foo
                    ├── message_loc: (1,0)-(1,3) = "foo"
                    ├── opening_loc: ∅
                    ├── arguments: ∅
                    ├── closing_loc: ∅
                    └── block:
                        @ BlockNode (location: (1,4)-(1,6))
                        ├── flags: ∅
                        ├── locals: []
                        ├── parameters: ∅
                        ├── body:
                        │   @ StatementsNode (location: (1,4)-(1,6))
                        │   ├── flags: ∅
                        │   └── body: (length: 1)
                        │       └── @ MissingNode (location: (1,4)-(1,6))
                        │           └── flags: newline
                        ├── opening_loc: (1,4)-(1,6) = "do"
                        └── closing_loc: (1,6)-(1,6) = ""
      AST
    end
  end

  def test_returns_ast_if_document_is_parsed
    with_server("foo = 123") do |server, uri|
      server.process_message(
        id: 1,
        method: "rubyLsp/textDocument/showSyntaxTree",
        params: { textDocument: { uri: uri } },
      )

      assert_equal(<<~AST, server.pop_response.response[:ast])
        @ ProgramNode (location: (1,0)-(1,9))
        ├── flags: ∅
        ├── locals: [:foo]
        └── statements:
            @ StatementsNode (location: (1,0)-(1,9))
            ├── flags: ∅
            └── body: (length: 1)
                └── @ LocalVariableWriteNode (location: (1,0)-(1,9))
                    ├── flags: newline
                    ├── name: :foo
                    ├── depth: 0
                    ├── name_loc: (1,0)-(1,3) = "foo"
                    ├── value:
                    │   @ IntegerNode (location: (1,6)-(1,9))
                    │   ├── flags: static_literal, decimal
                    │   └── value: 123
                    └── operator_loc: (1,4)-(1,5) = "="
      AST
    end
  end

  def test_returns_ast_for_a_selection
    source = <<~RUBY
      foo = 123
      bar = 456
      hello = 123
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "rubyLsp/textDocument/showSyntaxTree",
        params: {
          textDocument: { uri: uri },
          range: { start: { line: 0, character: 0 }, end: { line: 1, character: 9 } },
        },
      )

      assert_equal(<<~AST, server.pop_response.response[:ast])
        @ LocalVariableWriteNode (location: (1,0)-(1,9))
        ├── flags: newline
        ├── name: :foo
        ├── depth: 0
        ├── name_loc: (1,0)-(1,3) = "foo"
        ├── value:
        │   @ IntegerNode (location: (1,6)-(1,9))
        │   ├── flags: static_literal, decimal
        │   └── value: 123
        └── operator_loc: (1,4)-(1,5) = "="

        @ LocalVariableWriteNode (location: (2,0)-(2,9))
        ├── flags: newline
        ├── name: :bar
        ├── depth: 0
        ├── name_loc: (2,0)-(2,3) = "bar"
        ├── value:
        │   @ IntegerNode (location: (2,6)-(2,9))
        │   ├── flags: static_literal, decimal
        │   └── value: 456
        └── operator_loc: (2,4)-(2,5) = "="
      AST

      # We execute twice just to make sure we do not mutate by mistake.
      server.process_message(
        id: 1,
        method: "rubyLsp/textDocument/showSyntaxTree",
        params: {
          textDocument: { uri: uri },
          range: { start: { line: 1, character: 0 }, end: { line: 1, character: 9 } },
        },
      )
      refute_empty(server.pop_response.response[:ast])
    end
  end
end
