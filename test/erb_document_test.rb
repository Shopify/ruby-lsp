# typed: true
# frozen_string_literal: true

require "test_helper"

class ERBDocumentTest < Minitest::Test
  def test_parse_erb_document
    document = RubyLsp::ERBDocument.new(source: +<<~ERB, version: 1, uri: URI("file:///foo.html.erb"))
      <% x = 32 %>

      <p>
        <%= x %>
      </p>
    ERB

    refute_predicate(document, :syntax_error?)
  end

  def test_files_opened_with_syntax_errors_are_properly_marked
    document = RubyLsp::ERBDocument.new(source: +<<~ERB, version: 1, uri: URI("file:///foo.html.erb"))
      <% if true %>
    ERB

    assert_predicate(document, :syntax_error?)
  end
end
