# typed: true
# frozen_string_literal: true

require "test_helper"

class PrepareTypeHierarchyTest < Minitest::Test
  def test_prepare_type_hierarchy_returns_nil_if_no_node_at_position
    source = +<<~RUBY
      class Foo; end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/prepareTypeHierarchy", params: {
        textDocument: { uri: uri },
        position: { line: 0, character: 1 },
      })
      result = server.pop_response.response

      assert_nil(result)
    end
  end

  def test_prepare_type_hierarchy_returns_constant_path_name
    source = +<<~RUBY
      class Foo::Bar; end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/prepareTypeHierarchy", params: {
        textDocument: { uri: uri },
        position: { line: 0, character: 12 },
      })
      result = server.pop_response.response

      assert_equal("Foo::Bar", result.first.name)
    end
  end

  def test_prepare_type_hierarchy_returns_nil_if_constant_not_indexed
    source = <<~RUBY
      puts Bar
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/prepareTypeHierarchy", params: {
        textDocument: { uri: uri },
        position: { line: 0, character: 6 },
      })
      result = server.pop_response.response

      assert_nil(result)
    end
  end

  def test_prepare_type_hierarchy_returns_constant_name_if_indexed
    source = <<~RUBY
      class Bar; end
      puts Bar
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/prepareTypeHierarchy", params: {
        textDocument: { uri: uri },
        position: { line: 1, character: 6 },
      })
      result = server.pop_response.response

      assert_equal("Bar", result.first.name)
    end
  end

  def test_prepare_type_hierarchy_only_returns_the_first_entry
    source = <<~RUBY
      class Bar; end
      class Bar; end
      puts Bar
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/prepareTypeHierarchy", params: {
        textDocument: { uri: uri },
        position: { line: 2, character: 6 },
      })
      result = server.pop_response.response

      assert_equal(["Bar"], result.map(&:name))
    end
  end
end
