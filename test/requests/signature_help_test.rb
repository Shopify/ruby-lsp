# typed: true
# frozen_string_literal: true

require "test_helper"

class SignatureHelpTest < Minitest::Test
  def test_initial_request
    source = +<<~RUBY
      class Foo
        def bar(a, b)
        end

        def baz
          bar()
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 5, character: 7 },
        context: {
          triggerCharacter: "(",
          activeSignatureHelp: nil,
        },
      })
      result = server.pop_response.response
      signature = result.signatures.first

      assert_equal("bar(a, b)", signature.label)
      assert_equal(0, result.active_parameter)
    end
  end

  def test_concats_documentations_from_both_definitions
    source = <<~RUBY
      class Foo
        # first definition
        def bar(a, b)
        end

        def baz
          bar()
        end
      end

      class Foo
        # second definition
        def bar(c, d)
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 6, character: 7 },
        context: {
          triggerCharacter: "(",
          activeSignatureHelp: nil,
        },
      })
      result = server.pop_response.response
      signature = result.signatures.first

      assert_equal("bar(a, b)", signature.label)
      assert_equal(0, result.active_parameter)
      assert_match("first definition", signature.documentation.value)
      assert_match("second definition", signature.documentation.value)
    end
  end

  def test_help_after_comma
    source = +<<~RUBY
      class Foo
        def bar(a, b)
        end

        def baz
          bar(a,)
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/signatureHelp", params:  {
        textDocument: { uri: uri },
        position: { line: 5, character: 9 },
        context: {
          triggerCharacter: ",",
        },
      })
      result = server.pop_response.response
      signature = result.signatures.first

      assert_equal("bar(a, b)", signature.label)
      assert_equal(1, result.active_parameter)
    end
  end

  def test_keyword_arguments
    source = +<<~RUBY
      class Foo
        def bar(a:, b:)
        end

        def baz
          bar(b: 1,)
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/signatureHelp", params:  {
        textDocument: { uri: uri },
        position: { line: 5, character: 12 },
        context: {
          triggerCharacter: ",",
          activeSignatureHelp: nil,
        },
      })
      result = server.pop_response.response
      signature = result.signatures.first

      assert_equal("bar(a:, b:)", signature.label)
      assert_equal(1, result.active_parameter)
    end
  end

  def test_skipped_arguments
    source = +<<~RUBY
      class Foo
        def bar(a, b = 123, c:, d:)
        end

        def baz
          bar(a, c: 1,)
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 5, character: 15 },
        context: {
          triggerCharacter: ",",
          activeSignatureHelp: nil,
        },
      })
      result = server.pop_response.response
      signature = result.signatures.first
      assert_equal("bar(a, b = <default>, c:, d:)", signature.label)
      assert_equal(2, result.active_parameter)
    end
  end

  def test_help_for_splats
    source = +<<~RUBY
      class Foo
        def bar(*a)
        end

        def baz
          bar(a, b, c, d, e)
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 5, character: 20 },
        context: {},
      })
      result = server.pop_response.response
      signature = result.signatures.first
      assert_equal("bar(*a)", signature.label)
      assert_equal(0, result.active_parameter)
    end
  end

  def test_help_for_blocks
    source = +<<~RUBY
      class Foo
        def bar(a, &block)
        end

        def baz
          bar(a,)
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 5, character: 9 },
        context: {},
      })
      result = server.pop_response.response
      signature = result.signatures.first

      assert_equal("bar(a, &block)", signature.label)
      assert_equal(1, result.active_parameter)
    end
  end

  def test_requests_missing_context
    source = +<<~RUBY
      class Foo
        def bar(a, b)
        end

        def baz
          bar()
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 5, character: 7 },
      })
      result = server.pop_response.response
      signature = result.signatures.first

      assert_equal("bar(a, b)", signature.label)
      assert_equal(0, result.active_parameter)
    end
  end

  def test_help_in_nested_method_calls_no_arguments
    source = +<<~RUBY
      class Foo
        def bar(a)
        end

        def baz(b)
        end

        def qux
          bar(baz())
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 8, character: 11 },
        context: {},
      })
      result = server.pop_response.response
      signature = result.signatures.first

      assert_equal("bar(a)", signature.label)
      assert_equal(0, result.active_parameter)
    end
  end

  def test_help_in_nested_method_calls_with_arguments
    source = +<<~RUBY
      class Foo
        def bar(a)
        end

        def baz(b)
        end

        def qux
          bar(baz(123))
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 8, character: 11 },
        context: {},
      })
      result = server.pop_response.response
      signature = result.signatures.first

      assert_equal("bar(a)", signature.label)
      assert_equal(0, result.active_parameter)
    end
  end

  def test_singleton_methods
    source = +<<~RUBY
      class Foo
        def self.bar(a, b)
        end
      end

      Foo.bar()
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 5, character: 7 },
        context: {
          triggerCharacter: "(",
          activeSignatureHelp: nil,
        },
      })
      result = server.pop_response.response
      signature = result.signatures.first

      assert_equal("bar(a, b)", signature.label)
      assert_equal(0, result.active_parameter)
    end
  end

  def test_aliased_methods
    source = <<~RUBY
      class Parent
        def bar(a); end
      end

      class Child < Parent
        alias baz bar

        def do_something
          baz()
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 8, character: 8 },
        context: {},
      })
      result = server.pop_response.response
      signature = result.signatures.first

      assert_equal("baz(a)", signature.label)
      assert_equal(0, result.active_parameter)
    end
  end

  def test_help_is_disabled_on_typed_true
    source = +<<~RUBY
      # typed: true
      class Foo
        def bar(a, b)
        end

        def baz
          bar()
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 6, character: 7 },
        context: {
          triggerCharacter: "(",
          activeSignatureHelp: nil,
        },
      })
      assert_nil(server.pop_response.response)
    end
  end

  def test_guessed_types
    source = <<~RUBY
      class User
        def subscribe!(news_letter)
        end
      end

      user.subscribe!()
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 5, character: 15 },
        context: {},
      })
      result = server.pop_response.response
      signature = result.signatures.first

      assert_equal("subscribe!(news_letter)", signature.label)
      assert_match("Guessed receiver: User", signature.documentation.value)
    end
  end

  def test_automatically_detects_active_overload
    # First step overload: just a block
    source = <<~RUBY
      5.step()
    RUBY

    with_server(source) do |server, uri|
      index = server.instance_variable_get(:@global_state).index
      RubyIndexer::RBSIndexer.new(index).index_ruby_core

      server.process_message(id: 1, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 0, character: 7 },
        context: {},
      })

      result = server.pop_response.response
      signature = result.signatures[result.active_signature]
      assert_equal("step(limit = <default>, step = <default>, &<anonymous block>)", signature.label)
    end

    # Second step overload: with positional arguments
    source = <<~RUBY
      5.step(1)
    RUBY

    with_server(source) do |server, uri|
      index = server.instance_variable_get(:@global_state).index
      RubyIndexer::RBSIndexer.new(index).index_ruby_core

      server.process_message(id: 2, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 0, character: 8 },
        context: {},
      })

      result = server.pop_response.response
      signature = result.signatures[result.active_signature]
      assert_equal("step(limit = <default>, step = <default>, &<anonymous block>)", signature.label)
    end

    # Third step overload: with keyword arguments
    source = <<~RUBY
      5.step(to: 5)
    RUBY

    with_server(source) do |server, uri|
      index = server.instance_variable_get(:@global_state).index
      RubyIndexer::RBSIndexer.new(index).index_ruby_core

      server.process_message(id: 2, method: "textDocument/signatureHelp", params: {
        textDocument: { uri: uri },
        position: { line: 0, character: 8 },
        context: {},
      })

      result = server.pop_response.response
      signature = result.signatures[result.active_signature]
      assert_equal("step(by: <default>, to: <default>, &<anonymous block>)", signature.label)
    end
  end
end
