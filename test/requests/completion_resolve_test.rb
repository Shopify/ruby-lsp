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
        labelDetails: Interface::CompletionItemLabelDetails.new(
          description: "fake.rb",
        ),
        documentation: Interface::MarkupContent.new(
          kind: "markdown",
          value: markdown_from_index_entries("Foo::Bar", T.must(server.global_state.index["Foo::Bar"])),
        ),
      )
      assert_match(/This is a class that does things/, result[:documentation].value)
      assert_equal(expected.to_json, result.to_json)
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
        # Foo!
        def initialize
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
end
