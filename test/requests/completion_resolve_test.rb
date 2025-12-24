# typed: true
# frozen_string_literal: true

require "test_helper"

class CompletionResolveTest < Minitest::Test
  include RubyLsp::Requests::Support::Common

  Interface = LanguageServer::Protocol::Interface
  Constant = LanguageServer::Protocol::Constant

  def test_completion_resolve_for_constant
    source = +<<~RUBY
      module Foo
        # This is a class that does things
        class Bar
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, _uri|
      existing_item = {
        label: "Foo::Bar",
        insertText: "Bar",
      }

      server.process_message(id: 1, method: "completionItem/resolve", params: existing_item)

      result = server.pop_response.response

      expected = existing_item.merge(
        documentation: Interface::MarkupContent.new(
          kind: "markdown",
          value: markdown_from_index_entries(
            "Foo::Bar",
            server.global_state.index["Foo::Bar"], #: as !nil
          ),
        ),
      )
      assert_match(/This is a class that does things/, result[:documentation].value)
      assert_equal(expected.to_json, result.to_json)
      refute(result.key?(:labelDetails))
    end
  end

  def test_completion_resolve_with_owner_present
    source = +<<~RUBY
      class Bar
        def initialize
          # Bar!
          @a = 1
        end
      end

      class Foo
        def initialize
          # Foo!
          @a = 1
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, _uri|
      existing_item = {
        label: "@a",
        kind: RubyLsp::Constant::CompletionItemKind::FIELD,
        data: { owner_name: "Foo" },
      }

      server.process_message(id: 1, method: "completionItem/resolve", params: existing_item)

      result = server.pop_response.response
      assert_match(/Foo/, result[:documentation].value)

      existing_item = {
        label: "@a",
        kind: 5,
        data: { owner_name: "Bar" },
      }

      server.process_message(id: 1, method: "completionItem/resolve", params: existing_item)

      result = server.pop_response.response
      assert_match(/Bar/, result[:documentation].value)
    end
  end

  def test_inserts_method_parameters_in_label_details
    source = +<<~RUBY
      class Bar
        def foo(a, b, c)
        end

        def bar
          f
        end
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, _uri|
      existing_item = {
        label: "foo",
        kind: RubyLsp::Constant::CompletionItemKind::METHOD,
        data: { owner_name: "Bar" },
      }

      server.process_message(id: 1, method: "completionItem/resolve", params: existing_item)

      result = server.pop_response.response
      assert_match("(a, b, c)", result[:documentation].value)
    end
  end

  def test_indicates_signature_count_in_label_details
    source = +<<~RUBY
      String.try_convert
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, _uri|
      index = server.instance_variable_get(:@global_state).index
      RubyIndexer::RBSIndexer.new(index).index_ruby_core
      existing_item = {
        label: "try_convert",
        kind: RubyLsp::Constant::CompletionItemKind::METHOD,
        data: { owner_name: "String::<Class:String>" },
      }

      server.process_message(id: 1, method: "completionItem/resolve", params: existing_item)

      result = server.pop_response.response
      assert_match("try_convert(object)", result[:documentation].value)
      assert_match("(+2 overloads)", result[:documentation].value)
    end
  end

  def test_resolve_handles_method_aliases
    with_server("", stub_no_typechecker: true) do |server, _uri|
      index = server.instance_variable_get(:@global_state).index
      RubyIndexer::RBSIndexer.new(index).index_ruby_core

      # This is initially an unresolved method alias. In regular operations, completion runs first, resolves the alias
      # and then completionResolve doesn't have to do it. For the test, we need to do it manually
      index.resolve_method("kind_of?", "Kernel")

      existing_item = {
        label: "kind_of?",
        kind: RubyLsp::Constant::CompletionItemKind::METHOD,
        data: { owner_name: "Kernel" },
      }

      server.process_message(id: 1, method: "completionItem/resolve", params: existing_item)

      result = server.pop_response.response
      assert_match("**Definitions**: [kernel.rbs]", result[:documentation].value)
    end
  end

  def test_completion_documentation_for_guessed_types
    source = +<<~RUBY
      class User
        def foo(a, b, c)
        end
      end

      user.f
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, _uri|
      existing_item = {
        label: "foo",
        kind: RubyLsp::Constant::CompletionItemKind::METHOD,
        data: { owner_name: "User", guessed_type: "User" },
      }

      server.process_message(id: 1, method: "completionItem/resolve", params: existing_item)

      result = server.pop_response.response
      assert_match("Guessed receiver: User", result[:documentation].value)
      assert_match("Learn more about guessed types", result[:documentation].value)
    end
  end

  def test_resolve_for_keywords
    source = +<<~RUBY
      def foo
        yield
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, _uri|
      existing_item = {
        label: "yield",
        kind: RubyLsp::Constant::CompletionItemKind::KEYWORD,
        data: { keyword: true },
      }

      server.process_message(id: 1, method: "completionItem/resolve", params: existing_item)

      result = server.pop_response.response
      contents = result[:documentation].value

      assert_match("```ruby\nyield\n```", contents)
      assert_match(
        RubyLsp::KEYWORD_DOCS["yield"], #: as !nil
        contents,
      )
      assert_match("[Read more](#{RubyLsp::STATIC_DOCS_PATH}/yield.md)", contents)
    end
  end

  def test_resolve_for_require_completion
    source = +<<~RUBY
      require ""
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, _uri|
      existing_item = {
        label: "foo",
        kind: RubyLsp::Constant::CompletionItemKind::FILE,
        data: {},
      }

      server.process_message(id: 1, method: "completionItem/resolve", params: existing_item)

      result = server.pop_response.response
      assert_nil(result[:documentation])
    end
  end
end
