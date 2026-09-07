# typed: true
# frozen_string_literal: true

require "test_helper"

class TypeHierarchySupertypesTest < Minitest::Test
  def test_returns_nil_if_item_name_not_indexed
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

  def test_basic_object_has_no_implicit_supertype
    source = +<<~RUBY
      class BasicObject
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "BasicObject" },
      })

      result = server.pop_response.response
      assert_empty(result)
    end
  end

  def test_basic_object_includes_are_reported_without_implicit_object
    source = +<<~RUBY
      module M; end

      class BasicObject
        include M
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "BasicObject" },
      })

      result = server.pop_response.response
      assert_equal(["M"], result.map(&:name))
    end
  end

  def test_basic_object_singleton_has_no_implicit_supertype
    source = +<<~RUBY
      class BasicObject
        class << self
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "BasicObject::<BasicObject>" },
      })

      result = server.pop_response.response
      assert_empty(result)
    end
  end

  def test_adds_implicit_object_when_class_has_no_explicit_superclass
    source = +<<~RUBY
      class Foo; end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo" },
      })

      result = server.pop_response.response
      assert_equal(["Object"], result.map(&:name))
    end
  end

  def test_does_not_duplicate_object_when_class_explicitly_inherits_from_it
    source = +<<~RUBY
      class Foo < Object; end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo" },
      })

      result = server.pop_response.response
      assert_equal(["Object"], result.map(&:name))
    end
  end

  def test_module_has_no_implicit_object
    source = +<<~RUBY
      module Foo; end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo" },
      })

      result = server.pop_response.response
      assert_empty(result)
    end
  end

  def test_singleton_class_falls_back_to_object_singleton_when_no_explicit_parent
    source = +<<~RUBY
      class Foo
        class << self
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo::<Foo>" },
      })

      result = server.pop_response.response
      assert_equal(["Object::<Object>"], result.map(&:name))
    end
  end

  def test_singleton_ancestors_points_to_singleton_class_definition
    source = +<<~RUBY
      class Foo
        class << self
        end
      end

      class Bar < Foo
        class << self
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Bar::<Bar>" },
      })

      result = server.pop_response.response
      assert_equal(["Foo::<Foo>"], result.map(&:name))

      range = result.first.attributes[:range]
      assert_equal(1, range.attributes[:start].attributes[:line])
      assert_equal(2, range.attributes[:end].attributes[:line])
    end
  end

  def test_nested_singleton_class_falls_back_to_object_at_same_depth
    source = +<<~RUBY
      class Foo
        class << self
          class << self
          end
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo::<Foo>::<<Foo>>" },
      })

      result = server.pop_response.response
      assert_equal(["Object::<Object>::<<Object>>"], result.map(&:name))
    end
  end

  def test_singleton_class_inherits_from_parents_singleton_when_attached_has_explicit_superclass
    source = +<<~RUBY
      class Bar; end
      class Foo < Bar
        class << self
        end
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo::<Foo>" },
      })

      result = server.pop_response.response
      assert_equal(["Bar::<Bar>"], result.map(&:name))
    end
  end

  def test_returns_direct_superclass
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
      assert_equal(["Object"], result.map(&:name))
    end
  end

  def test_returns_includes_and_prepends
    source = <<~RUBY
      module A; end
      module B; end
      class Parent; end

      class Foo < Parent
        include A
        prepend B
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo" },
      })

      result = server.pop_response.response
      assert_equal(["Parent", "A", "B"].sort, result.map(&:name).sort)
    end
  end

  def test_excludes_extend_from_class_supertypes
    source = <<~RUBY
      module A; end
      module M; end
      class Foo
        include A
        extend M
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo" },
      })
      result = server.pop_response.response

      names = result.map(&:name)
      assert_includes(names, "A")
      refute_includes(names, "M")
    end
  end

  def test_aggregates_mixins_across_reopens_and_dedupes
    source = <<~RUBY
      module A; end
      module B; end

      class Foo
        include A
      end

      class Foo
        include B
      end

      class Foo
        include A
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo" },
      })
      result = server.pop_response.response

      names = result.map(&:name).sort
      assert_equal(["A", "B", "Object"], names)
    end
  end

  def test_module_supertypes_include_mixins_only
    source = <<~RUBY
      module A; end
      module M
        include A
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "M" },
      })
      result = server.pop_response.response

      assert_equal(["A"], result.map(&:name))
    end
  end

  def test_uses_fully_qualified_name_from_data_when_present
    source = <<~RUBY
      class Parent; end
      class Foo < Parent; end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: {
          name: "<invalid name. Should use fully qualified name instead>",
          data: { fully_qualified_name: "Foo" },
        },
      })

      result = server.pop_response.response
      assert_equal(["Parent"], result.map(&:name))
    end
  end

  def test_skips_unresolved_supertype_references
    source = <<~RUBY
      class Foo < ReferenceThatDoesNotExist; end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo" },
      })

      result = server.pop_response.response
      assert_empty(result)
    end
  end

  def test_mixes_resolved_and_unresolved_references
    source = <<~RUBY
      module A; end

      class Foo
        include DoesNotExist
        include A
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo" },
      })

      result = server.pop_response.response
      assert_equal(["A", "Object"], result.map(&:name))
    end
  end

  def test_returned_items_embed_fully_qualified_name_in_data
    source = <<~RUBY
      class Parent; end
      class Foo < Parent; end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(id: 1, method: "typeHierarchy/supertypes", params: {
        textDocument: { uri: uri },
        item: { name: "Foo" },
      })
      result = server.pop_response.response

      parent = result.first
      assert_equal("Parent", parent.name)
      assert_equal("Parent", parent.attributes[:data][:fully_qualified_name])
    end
  end
end
