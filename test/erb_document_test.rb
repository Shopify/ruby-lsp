# typed: true
# frozen_string_literal: true

require "test_helper"

class ERBDocumentTest < Minitest::Test
  def test_erb_file_is_properly_parsed
    document = RubyLsp::ERBDocument.new(source: +<<~ERB, version: 1, uri: URI("file:///foo.erb"))
      <ul>
        <li><%= foo %><li>
        <li><%= bar %><li>
        <li><%== baz %><li>
        <li><%- quz %><li>
      </ul>
    ERB

    document.parse

    refute_predicate(document, :syntax_error?)
    assert_equal(
      "    \n          foo       \n          bar       \n           baz       \n          quz       \n     \n",
      document.parse_result.source.source,
    )
  end

  def test_erb_file_parses_in_eval_context
    document = RubyLsp::ERBDocument.new(source: +<<~ERB, version: 1, uri: URI("file:///foo.erb"))
      <html>
        <head>
          <%= yield :head %>
        </head>
        <body>
          <%= yield %>
        </body>
      </html>
    ERB

    document.parse

    refute_predicate(document, :syntax_error?)
    assert_equal(
      "      \n        \n        yield :head   \n         \n        \n        yield   \n         \n       \n",
      document.parse_result.source.source,
    )
  end

  def test_erb_document_handles_windows_newlines
    document = RubyLsp::ERBDocument.new(source: "<%=\r\nbar %>", version: 1, uri: URI("file:///foo.erb"))
    document.parse

    refute_predicate(document, :syntax_error?)
    assert_equal("   \r\nbar   ", document.parse_result.source.source)
  end

  def test_erb_syntax_error_doesnt_cause_crash
    [
      "<%=",
      "<%",
      "<%-",
      "<%#",
      "<%= foo %>\n<%= bar",
      "<%= foo %\n<%= bar %>",
    ].each do |source|
      document = RubyLsp::ERBDocument.new(source: source, version: 1, uri: URI("file:///foo.erb"))
      document.parse
    end
  end

  def test_failing_to_parse_indicates_syntax_error
    document = RubyLsp::ERBDocument.new(source: +<<~ERB, version: 1, uri: URI("file:///foo.erb"))
      <ul>
        <li><%= foo %><li>
        <li><%= end %><li>
      </ul>
    ERB

    assert_predicate(document, :syntax_error?)
  end

  def test_locate
    document = RubyLsp::ERBDocument.new(source: <<~ERB, version: 1, uri: URI("file:///foo/bar.erb"))
      <% Post.all.each do |post| %>
        <h1><%= post.title %></h1>
      <% end %>
    ERB

    # Locate the `Post` class
    node_context = document.locate_node({ line: 0, character: 3 })
    assert_instance_of(Prism::ConstantReadNode, node_context.node)
    assert_equal("Post", T.cast(node_context.node, Prism::ConstantReadNode).location.slice)

    # Locate the `each` call from block
    node_context = document.locate_node({ line: 0, character: 17 })
    assert_instance_of(Prism::BlockNode, node_context.node)
    assert_equal(:each, T.must(node_context.call_node).name)

    # Locate the `title` invocation
    node_context = document.locate_node({ line: 1, character: 15 })
    assert_equal("title", T.cast(node_context.node, Prism::CallNode).message)
  end

  def test_cache_set_and_get
    document = RubyLsp::ERBDocument.new(source: +"", version: 1, uri: URI("file:///foo/bar.erb"))
    value = [1, 2, 3]

    assert_equal(value, document.cache_set("textDocument/semanticHighlighting", value))
    assert_equal(value, document.cache_get("textDocument/semanticHighlighting"))
  end
end
