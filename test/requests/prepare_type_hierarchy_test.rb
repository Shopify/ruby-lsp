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

  def test_prepare_type_hierarchy_on_parent_of_compact_namespace
    source = +<<~RUBY
      class Foo; end
      class Foo::Bar; end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/prepareTypeHierarchy", params: {
        textDocument: { uri: uri },
        position: { line: 1, character: 7 },
      })

      result = server.pop_response.response
      assert_equal("Foo", result.first.name)
    end
  end

  def test_prepare_type_hierarchy_on_singleton_class_block
    source = +<<~RUBY
      class Foo
        class << self
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/prepareTypeHierarchy", params: {
        textDocument: { uri: uri },
        position: { line: 1, character: 4 },
      })

      result = server.pop_response.response
      assert_equal("Foo::<Foo>", result.first.name)
    end
  end

  def test_prepare_type_hierarchy_on_nested_singleton_class_block
    source = +<<~RUBY
      class Foo
        class << self
          class << self
          end
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/prepareTypeHierarchy", params: {
        textDocument: { uri: uri },
        position: { line: 2, character: 6 },
      })

      result = server.pop_response.response
      assert_equal("Foo::<Foo>::<<Foo>>", result.first.name)
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

  def test_nesting_constant_references_are_resolved
    source = +<<~RUBY
      module Bar; end

      module Foo
        class Bar::Baz
          class << self
          end
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/prepareTypeHierarchy", params: {
        textDocument: { uri: uri },
        position: { line: 4, character: 6 },
      })

      result = server.pop_response.response
      assert_equal("Bar::Baz::<Baz>", result.first.name)
    end
  end

  def test_singleton_class_targets
    source = +<<~RUBY
      module Bar; end

      module Foo
        class << Bar
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/prepareTypeHierarchy", params: {
        textDocument: { uri: uri },
        position: { line: 3, character: 11 },
      })

      result = server.pop_response.response
      assert_equal("Bar::<Bar>", result.first.name)
    end
  end

  def test_parent_scopes_are_resolved
    source = +<<~RUBY
      module Qux; end
      module Bar
        include Qux
      end

      class Zip; end

      module Foo
        class Bar::Baz < Zip
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/prepareTypeHierarchy", params: {
        textDocument: { uri: uri },
        position: { line: 8, character: 8 },
      })

      result = server.pop_response.response
      assert_equal("Bar", result.first.name)

      server.process_message(id: 2, method: "textDocument/prepareTypeHierarchy", params: {
        textDocument: { uri: uri },
        position: { line: 8, character: 13 },
      })

      result = server.pop_response.response
      assert_equal("Bar::Baz", result.first.name)
    end
  end

  def test_dynamic_singleton_target
    source = +<<~RUBY
      module Bar; end

      class Foo
        class << Bar::baz
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "textDocument/prepareTypeHierarchy", params: {
        textDocument: { uri: uri },
        position: { line: 3, character: 16 },
      })

      assert_nil(server.pop_response.response)
    end
  end
end
