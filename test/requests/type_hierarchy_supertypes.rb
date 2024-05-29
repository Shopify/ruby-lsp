# typed: true
# frozen_string_literal: true

require "test_helper"

class TypeHierarchySupertypesTest < Minitest::Test
  def test_type_hierarchy_supertypes_returns_nil_if_item_name_not_indexed
    source = +<<~RUBY
      class Foo; end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Bar" },
      })
      result = server.pop_response.response

      assert_nil(result)
    end
  end

  def test_type_hierarchy_supertypes_returns_empty_array_if_no_supertypes
    source = +<<~RUBY
      class Foo::Bar; end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo::Bar" },
      })
      result = server.pop_response.response

      assert_empty(result)
    end
  end

  def test_type_hierarchy_returns_supertypes
    source = <<~RUBY
      module Foo
        class Bar; end
        class Baz < Bar; end
        class Qux < Baz; end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo::Qux" },
      })
      result = server.pop_response.response

      assert_equal(["Foo::Baz"], result.map(&:name))

      server.process_message(id: 2, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo::Baz" },
      })
      result = server.pop_response.response

      assert_equal(["Foo::Bar"], result.map(&:name))

      server.process_message(id: 2, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo::Bar" },
      })
      result = server.pop_response.response

      assert_empty(result)
    end
  end
end
