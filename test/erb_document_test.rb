# typed: true
# frozen_string_literal: true

require "test_helper"

class ERBDocumentTest < Minitest::Test
  def setup
    @global_state = RubyLsp::GlobalState.new
  end

  def test_erb_file_is_properly_parsed
    source = +<<~ERB
      <ul>
        <li><%= foo %><li>
        <li><%= bar %><li>
        <li><%== baz %><li>
        <li><%- quz %><li>
      </ul>
    ERB
    document = RubyLsp::ERBDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///foo.erb"),
      global_state: @global_state,
    )

    document.parse!

    refute_predicate(document, :syntax_error?)
    assert_equal(
      "    \n          foo       \n          bar       \n           baz       \n          quz       \n     \n",
      document.parse_result.source.source,
    )
  end

  def test_erb_file_parses_in_eval_context
    source = +<<~ERB
      <html>
        <head>
          <%= yield :head %>
        </head>
        <body>
          <%= yield %>
        </body>
      </html>
    ERB
    document = RubyLsp::ERBDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///foo.erb"),
      global_state: @global_state,
    )

    document.parse!

    refute_predicate(document, :syntax_error?)
    assert_equal(
      "      \n        \n        yield :head   \n         \n        \n        yield   \n         \n       \n",
      document.parse_result.source.source,
    )
  end

  def test_erb_document_handles_windows_newlines
    document = RubyLsp::ERBDocument.new(
      source: "<%=\r\nbar %>",
      version: 1,
      uri: URI("file:///foo.erb"),
      global_state: @global_state,
    )
    document.parse!

    refute_predicate(document, :syntax_error?)
    assert_equal("   \r\nbar   ", document.parse_result.source.source)
  end

  def test_erb_comments_are_not_parsed_as_ruby
    source = <<~ERB
      <%# A comment with a first line,
          followed by prose that must not become Ruby method calls %>
      <%#- A second comment with a trimmed closing tag -%>
      <%= visible_method_call %>
    ERB
    document = RubyLsp::ERBDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///foo.erb"),
      global_state: @global_state,
    )
    document.parse!

    ruby_source = document.parse_result.source.source
    refute_includes(ruby_source, "followed by prose")
    assert_includes(ruby_source, "visible_method_call")
    assert_equal(source.length, ruby_source.length)
    assert_equal(source.lines.length, ruby_source.lines.length)
    assert_equal(
      [:visible_method_call],
      document.ast.statements.body.grep(Prism::CallNode).map(&:name),
    )
  end

  def test_erb_syntax_error_does_not_cause_crash
    [
      "<%=",
      "<%",
      "<%-",
      "<%#",
      "<%= foo %>\n<%= bar",
      "<%= foo %\n<%= bar %>",
    ].each do |source|
      document = RubyLsp::ERBDocument.new(
        source: source,
        version: 1,
        uri: URI("file:///foo.erb"),
        global_state: @global_state,
      )
      document.parse!
    end
  end

  def test_failing_to_parse_indicates_syntax_error
    source = +<<~ERB
      <ul>
        <li><%= foo %><li>
        <li><%= end %><li>
      </ul>
    ERB
    document = RubyLsp::ERBDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///foo.erb"),
      global_state: @global_state,
    )

    assert_predicate(document, :syntax_error?)
  end

  def test_locate
    source = <<~ERB
      <% Post.all.each do |post| %>
        <h1><%= post.title %></h1>
      <% end %>
    ERB
    document = RubyLsp::ERBDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///foo/bar.erb"),
      global_state: @global_state,
    )

    # Locate the `Post` class
    node_context = document.locate_node({ line: 0, character: 3 })
    assert_instance_of(Prism::ConstantReadNode, node_context.node)
    assert_equal(
      "Post",
      node_context.node #: as Prism::ConstantReadNode
        .location.slice,
    )

    # Locate the `each` call from block
    node_context = document.locate_node({ line: 0, character: 17 })
    assert_instance_of(Prism::BlockNode, node_context.node)
    assert_equal(
      :each,
      node_context.call_node #: as !nil
        .name,
    )

    # Locate the `title` invocation
    node_context = document.locate_node({ line: 1, character: 15 })
    assert_equal(
      "title",
      node_context.node #: as Prism::CallNode
        .message,
    )
  end

  def test_cache_set_and_get
    document = RubyLsp::ERBDocument.new(
      source: +"",
      version: 1,
      uri: URI("file:///foo/bar.erb"),
      global_state: @global_state,
    )
    value = [1, 2, 3]

    assert_equal(value, document.cache_set("textDocument/semanticHighlighting", value))
    assert_equal(value, document.cache_get("textDocument/semanticHighlighting"))
  end

  def test_keeps_track_of_virtual_host_language_source
    source = +<<~ERB
      <ul>
        <li><%= foo %><li>
        <li><%= end %><li>
      </ul>
    ERB
    document = RubyLsp::ERBDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///foo.erb"),
      global_state: @global_state,
    )

    assert_equal(<<~HTML, document.host_language_source)
      <ul>
        <li>          <li>
        <li>          <li>
      </ul>
    HTML
  end

  def test_erb_is_parsed_as_a_partial_script
    source = +<<~ERB
      <ul>
        <li><%= redo %><li>
      </ul>
    ERB
    document = RubyLsp::ERBDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///foo.erb"),
      global_state: @global_state,
    )

    document.parse!

    refute_predicate(document, :syntax_error?)
  end
end
