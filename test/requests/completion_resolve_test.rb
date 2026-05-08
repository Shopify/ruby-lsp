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
        data: { fully_qualified_name: "Foo::Bar" },
      }

      server.process_message(id: 1, method: "completionItem/resolve", params: existing_item)

      result = server.pop_response.response

      declaration = server.global_state.graph["Foo::Bar"] #: as !nil
      expected = existing_item.merge(
        documentation: Interface::MarkupContent.new(
          kind: "markdown",
          value: markdown_from_definitions(
            "Foo::Bar",
            declaration.definitions,
            RubyLsp::Requests::CompletionResolve::MAX_DOCUMENTATION_ENTRIES,
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
    skip("[RUBYDEX] needs method signatures")

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
    skip("[RUBYDEX] needs method signatures. Change this test to index an RBS document with overloaded signatures")

    with_server("String.try_convert", stub_no_typechecker: true) do |server, _uri|
      existing_item = {
        label: "try_convert",
        kind: RubyLsp::Constant::CompletionItemKind::METHOD,
        data: { owner_name: "String::<String>" },
      }

      server.process_message(id: 1, method: "completionItem/resolve", params: existing_item)

      result = server.pop_response.response
      assert_match("try_convert(object)", result[:documentation].value)
      assert_match("(+2 overloads)", result[:documentation].value)
    end
  end

  def test_resolve_handles_method_aliases
    skip("[RUBYDEX] need to expose method alias targets in the Ruby API")

    source = +<<~RUBY
      class Bar
        # The original method
        def foo
        end

        alias_method :baz, :foo
      end
    RUBY

    with_server(source, stub_no_typechecker: true) do |server, _uri|
      existing_item = {
        label: "baz",
        kind: RubyLsp::Constant::CompletionItemKind::METHOD,
        data: { owner_name: "Bar" },
      }

      server.process_message(id: 1, method: "completionItem/resolve", params: existing_item)

      result = server.pop_response.response
      docs = result[:documentation].value
      assert_match("**Definitions**: [fake.rb]", docs)
      assert_match("The original method", docs)
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

  def test_completion_resolve_for_built_in_constant
    with_server("Object", stub_no_typechecker: true) do |server, _uri|
      existing_item = {
        label: "Object",
        insertText: "Object",
        data: { fully_qualified_name: "Object" },
      }

      server.process_message(id: 1, method: "completionItem/resolve", params: existing_item)

      result = server.pop_response.response
      contents = result[:documentation].value
      refute_match("rubydex:built-in", contents)
      refute_match("[built-in]", contents)
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

      keyword = server.global_state.graph.keyword("yield") #: as !nil
      assert_match("```ruby\nyield\n```", contents)
      assert_match(keyword.documentation, contents)
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
