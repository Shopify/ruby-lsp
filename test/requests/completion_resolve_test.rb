# typed: true
# frozen_string_literal: true

require "test_helper"

class CompletionResolveTest < Minitest::Test
  include RubyLsp::Requests::Support::Common

  Interface = LanguageServer::Protocol::Interface
  Constant = LanguageServer::Protocol::Constant

  def test_completion_resolve_for_constant
    stub_no_typechecker
    source = +<<~RUBY
      class Foo
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "completionItem/resolve", params: {
        label: "Foo",
      })

      result = server.pop_response.response

      expected = Interface::CompletionItem.new(
        label: "Foo",
        label_details: Interface::CompletionItemLabelDetails.new(
          description: "fake.rb",
        ),
        documentation: Interface::MarkupContent.new(
          kind: "markdown",
          value: markdown_from_index_entries("Foo", T.must(server.index["Foo"])),
        ),
      )
      assert_equal(expected.to_json, result.to_json)
    end
  end
end
