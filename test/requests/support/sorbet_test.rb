# typed: true
# frozen_string_literal: true

require "test_helper"

class SorbetTest < Minitest::Test
  extend T::Sig

  def test_abstract!
    assert(annotation?("abstract!"))
    assert(annotation?("abstract!()"))

    refute(annotation?("abstract!(x)"))
    refute(annotation?("abstract!(x, y)"))

    refute(annotation?("T.abstract!"))
    refute(annotation?("T.abstract!()"))
    refute(annotation?("T.abstract!(x)"))
    refute(annotation?("T.abstract!(x, y)"))

    refute(annotation?("C.abstract!"))
    refute(annotation?("C.abstract!()"))
    refute(annotation?("C.abstract!(x)"))
    refute(annotation?("C.abstract!(x, y)"))
  end

  def test_absurd
    assert(annotation?("T.absurd(x)"))

    refute(annotation?("T.absurd"))
    refute(annotation?("T.absurd()"))
    refute(annotation?("T.absurd(x, y)"))

    refute(annotation?("absurd"))
    refute(annotation?("absurd()"))
    refute(annotation?("absurd(x)"))
    refute(annotation?("absurd(x, y)"))

    refute(annotation?("C.absurd"))
    refute(annotation?("C.absurd()"))
    refute(annotation?("C.absurd(x)"))
    refute(annotation?("C.absurd(x, y)"))
  end

  def test_all
    assert(annotation?("T.all(x, y)"))
    assert(annotation?("T.all(x, y, z)"))

    refute(annotation?("T.all"))
    refute(annotation?("T.all()"))
    refute(annotation?("T.all(x)"))

    refute(annotation?("all"))
    refute(annotation?("all()"))
    refute(annotation?("all(x)"))
    refute(annotation?("all(x, y)"))
    refute(annotation?("all(x, y, z)"))

    refute(annotation?("C.all"))
    refute(annotation?("C.all()"))
    refute(annotation?("C.all(x)"))
    refute(annotation?("C.all(x, y)"))
    refute(annotation?("C.all(x, y, z)"))
  end

  def test_any
    assert(annotation?("T.any(x, y)"))
    assert(annotation?("T.any(x, y, z)"))

    refute(annotation?("T.any"))
    refute(annotation?("T.any()"))
    refute(annotation?("T.any(x)"))

    refute(annotation?("any"))
    refute(annotation?("any()"))
    refute(annotation?("any(x)"))
    refute(annotation?("any(x, y)"))
    refute(annotation?("any(x, y, z)"))

    refute(annotation?("C.any"))
    refute(annotation?("C.any()"))
    refute(annotation?("C.any(x)"))
    refute(annotation?("C.any(x, y)"))
    refute(annotation?("C.any(x, y, z)"))
  end

  def test_assert_type!
    assert(annotation?("T.assert_type!(x, y)"))

    refute(annotation?("T.assert_type!"))
    refute(annotation?("T.assert_type!()"))
    refute(annotation?("T.assert_type!(x)"))
    refute(annotation?("T.assert_type!(x, y, z)"))

    refute(annotation?("assert_type!"))
    refute(annotation?("assert_type!()"))
    refute(annotation?("assert_type!(x)"))
    refute(annotation?("assert_type!(x, y)"))
    refute(annotation?("assert_type!(x, y, z)"))

    refute(annotation?("C.assert_type!"))
    refute(annotation?("C.assert_type!()"))
    refute(annotation?("C.assert_type!(x)"))
    refute(annotation?("C.assert_type!(x, y)"))
    refute(annotation?("C.assert_type!(x, y, z)"))
  end

  def test_attached_class
    assert(annotation?("T.attached_class"))
    assert(annotation?("T.attached_class()"))

    refute(annotation?("T.attached_class(x)"))
    refute(annotation?("T.attached_class(x, y)"))

    refute(annotation?("attached_class"))
    refute(annotation?("attached_class()"))
    refute(annotation?("attached_class(x)"))
    refute(annotation?("attached_class(x, y)"))

    refute(annotation?("C.attached_class"))
    refute(annotation?("C.attached_class()"))
    refute(annotation?("C.attached_class(x)"))
    refute(annotation?("C.attached_class(x, y)"))
  end

  def test_cast
    assert(annotation?("T.cast(x, y)"))

    refute(annotation?("T.cast"))
    refute(annotation?("T.cast()"))
    refute(annotation?("T.cast(x)"))
    refute(annotation?("T.cast(x, y, z)"))

    refute(annotation?("cast"))
    refute(annotation?("cast()"))
    refute(annotation?("cast(x)"))
    refute(annotation?("cast(x, y)"))
    refute(annotation?("cast(x, y, z)"))

    refute(annotation?("C.cast"))
    refute(annotation?("C.cast()"))
    refute(annotation?("C.cast(x)"))
    refute(annotation?("C.cast(x, y)"))
    refute(annotation?("C.cast(x, y, z)"))
  end

  def test_class_of
    assert(annotation?("T.class_of(x)"))

    refute(annotation?("T.class_of"))
    refute(annotation?("T.class_of()"))
    refute(annotation?("T.class_of(x, y)"))
    refute(annotation?("T.class_of(x, y, z)"))

    refute(annotation?("class_of"))
    refute(annotation?("class_of()"))
    refute(annotation?("class_of(x)"))
    refute(annotation?("class_of(x, y)"))
    refute(annotation?("class_of(x, y, z)"))

    refute(annotation?("C.class_of"))
    refute(annotation?("C.class_of()"))
    refute(annotation?("C.class_of(x)"))
    refute(annotation?("C.class_of(x, y)"))
    refute(annotation?("C.class_of(x, y, z)"))
  end

  def test_enums
    assert(annotation?("enums {}"))
    assert(annotation?("enums() {}"))

    refute(annotation?("enums(x) {}"))
    refute(annotation?("enums(x, y) {}"))
    refute(annotation?("enums(x, y, z) {}"))

    refute(annotation?("T.enums {}"))
    refute(annotation?("T.enums() {}"))
    refute(annotation?("T.enums(x) {}"))
    refute(annotation?("T.enums(x, y) {}"))
    refute(annotation?("T.enums(x, y, z) {}"))

    refute(annotation?("C.enums {}"))
    refute(annotation?("C.enums() {}"))
    refute(annotation?("C.enums(x) {}"))
    refute(annotation?("C.enums(x, y) {}"))
    refute(annotation?("C.enums(x, y, z) {}"))
  end

  def test_interface!
    assert(annotation?("interface!"))
    assert(annotation?("interface!()"))

    refute(annotation?("interface!(x)"))
    refute(annotation?("interface!(x, y)"))

    refute(annotation?("T.interface!"))
    refute(annotation?("T.interface!()"))
    refute(annotation?("T.interface!(x)"))
    refute(annotation?("T.interface!(x, y)"))

    refute(annotation?("C.interface!"))
    refute(annotation?("C.interface!()"))
    refute(annotation?("C.interface!(x)"))
    refute(annotation?("C.interface!(x, y)"))
  end

  def test_let
    assert(annotation?("T.let(x, y)"))

    refute(annotation?("T.let"))
    refute(annotation?("T.let()"))
    refute(annotation?("T.let(x)"))
    refute(annotation?("T.let(x, y, z)"))

    refute(annotation?("let"))
    refute(annotation?("let()"))
    refute(annotation?("let(x)"))
    refute(annotation?("let(x, y)"))
    refute(annotation?("let(x, y, z)"))

    refute(annotation?("C.let"))
    refute(annotation?("C.let()"))
    refute(annotation?("C.let(x)"))
    refute(annotation?("C.let(x, y)"))
    refute(annotation?("C.let(x, y, z)"))
  end

  def test_mixes_in_class_methods
    assert(annotation?("mixes_in_class_methods(x)"))

    refute(annotation?("mixes_in_class_methods"))
    refute(annotation?("mixes_in_class_methods()"))
    refute(annotation?("mixes_in_class_methods(x, y)"))

    refute(annotation?("T.mixes_in_class_methods"))
    refute(annotation?("T.mixes_in_class_methods()"))
    refute(annotation?("T.mixes_in_class_methods(x)"))
    refute(annotation?("T.mixes_in_class_methods(x, y)"))

    refute(annotation?("C.mixes_in_class_methods"))
    refute(annotation?("C.mixes_in_class_methods()"))
    refute(annotation?("C.mixes_in_class_methods(x)"))
    refute(annotation?("C.mixes_in_class_methods(x, y)"))
  end

  def test_must
    assert(annotation?("T.must(x)"))

    refute(annotation?("T.must"))
    refute(annotation?("T.must()"))
    refute(annotation?("T.must(x, y)"))

    refute(annotation?("must"))
    refute(annotation?("must()"))
    refute(annotation?("must(x)"))
    refute(annotation?("must(x, y)"))

    refute(annotation?("C.must"))
    refute(annotation?("C.must()"))
    refute(annotation?("C.must(x)"))
    refute(annotation?("C.must(x, y)"))
  end

  def test_must_because
    assert(annotation?("T.must_because(x) {}"))

    refute(annotation?("T.must_because {}"))
    refute(annotation?("T.must_because() {}"))
    refute(annotation?("T.must_because(x, y) {}"))

    refute(annotation?("must_because {}"))
    refute(annotation?("must_because() {}"))
    refute(annotation?("must_because(x) {}"))
    refute(annotation?("must_because(x, y) {}"))

    refute(annotation?("C.must_because {}"))
    refute(annotation?("C.must_because() {}"))
    refute(annotation?("C.must_because(x) {}"))
    refute(annotation?("C.must_because(x, y) {}"))
  end

  def test_nilable
    assert(annotation?("T.nilable(x)"))

    refute(annotation?("T.nilable"))
    refute(annotation?("T.nilable()"))
    refute(annotation?("T.nilable(x, y)"))

    refute(annotation?("nilable"))
    refute(annotation?("nilable()"))
    refute(annotation?("nilable(x)"))
    refute(annotation?("nilable(x, y)"))

    refute(annotation?("C.nilable"))
    refute(annotation?("C.nilable()"))
    refute(annotation?("C.nilable(x)"))
    refute(annotation?("C.nilable(x, y)"))
  end

  def test_noreturn
    assert(annotation?("T.noreturn"))
    assert(annotation?("T.noreturn()"))

    refute(annotation?("T.noreturn(x)"))
    refute(annotation?("T.noreturn(x, y)"))

    refute(annotation?("noreturn"))
    refute(annotation?("noreturn()"))
    refute(annotation?("noreturn(x)"))
    refute(annotation?("noreturn(x, y)"))

    refute(annotation?("C.noreturn"))
    refute(annotation?("C.noreturn()"))
    refute(annotation?("C.noreturn(x)"))
    refute(annotation?("C.noreturn(x, y)"))
  end

  def test_requires_ancestor
    assert(annotation?("requires_ancestor {}"))
    assert(annotation?("requires_ancestor() {}"))

    refute(annotation?("requires_ancestor(Kernel) {}"))

    refute(annotation?("T.requires_ancestor {}"))
    refute(annotation?("T.requires_ancestor() {}"))
    refute(annotation?("T.requires_ancestor(Kernel) {}"))

    refute(annotation?("C.requires_ancestor {}"))
    refute(annotation?("C.requires_ancestor() {}"))
    refute(annotation?("C.requires_ancestor(Kernel) {}"))
  end

  def test_reveal_type
    assert(annotation?("T.reveal_type(x)"))

    refute(annotation?("T.reveal_type"))
    refute(annotation?("T.reveal_type()"))
    refute(annotation?("T.reveal_type(x, y)"))

    refute(annotation?("reveal_type"))
    refute(annotation?("reveal_type()"))
    refute(annotation?("reveal_type(x)"))
    refute(annotation?("reveal_type(x, y)"))

    refute(annotation?("C.reveal_type"))
    refute(annotation?("C.reveal_type()"))
    refute(annotation?("C.reveal_type(x)"))
    refute(annotation?("C.reveal_type(x, y)"))
  end

  def test_self_type
    assert(annotation?("T.self_type"))
    assert(annotation?("T.self_type()"))

    refute(annotation?("T.self_type(x)"))
    refute(annotation?("T.self_type(x, y)"))

    refute(annotation?("self_type"))
    refute(annotation?("self_type()"))
    refute(annotation?("self_type(x)"))
    refute(annotation?("self_type(x, y)"))

    refute(annotation?("C.self_type"))
    refute(annotation?("C.self_type()"))
    refute(annotation?("C.self_type(x)"))
    refute(annotation?("C.self_type(x, y)"))
  end

  def test_sealed!
    assert(annotation?("sealed!"))
    assert(annotation?("sealed!()"))

    refute(annotation?("sealed!(x)"))
    refute(annotation?("sealed!(x, y)"))

    refute(annotation?("T.sealed!"))
    refute(annotation?("T.sealed!()"))
    refute(annotation?("T.sealed!(x)"))
    refute(annotation?("T.sealed!(x, y)"))

    refute(annotation?("C.sealed!"))
    refute(annotation?("C.sealed!()"))
    refute(annotation?("C.sealed!(x)"))
    refute(annotation?("C.sealed!(x, y)"))
  end

  def test_sig
    assert(annotation?("sig {}"))
    assert(annotation?("sig() {}"))

    refute(annotation?("sig(x) {}"))
    refute(annotation?("sig(x, y) {}"))

    refute(annotation?("T.sig {}"))
    refute(annotation?("T.sig() {}"))
    refute(annotation?("T.sig(x) {}"))
    refute(annotation?("T.sig(x, y) {}"))

    refute(annotation?("C.sig {}"))
    refute(annotation?("C.sig() {}"))
    refute(annotation?("C.sig(x) {}"))
    refute(annotation?("C.sig(x, y) {}"))
  end

  def test_type_member
    assert(annotation?("type_member"))
    assert(annotation?("type_member()"))
    assert(annotation?("type_member(x)"))

    refute(annotation?("type_member(x, y)"))

    refute(annotation?("T.type_member"))
    refute(annotation?("T.type_member()"))
    refute(annotation?("T.type_member(x)"))
    refute(annotation?("T.type_member(x, y)"))

    refute(annotation?("C.type_member"))
    refute(annotation?("C.type_member()"))
    refute(annotation?("C.type_member(x)"))
    refute(annotation?("C.type_member(x, y)"))
  end

  def test_type_template
    assert(annotation?("type_template"))
    assert(annotation?("type_template()"))
    assert(annotation?("type_template {}"))
    assert(annotation?("type_template() {}"))

    refute(annotation?("type_template(x)"))
    refute(annotation?("type_template(x, y)"))
    refute(annotation?("type_template(x) {}"))
    refute(annotation?("type_template(x, y) {}"))

    refute(annotation?("T.type_template"))
    refute(annotation?("T.type_template()"))
    refute(annotation?("T.type_template(x)"))
    refute(annotation?("T.type_template(x, y)"))
    refute(annotation?("T.type_template {}"))
    refute(annotation?("T.type_template() {}"))
    refute(annotation?("T.type_template(x) {}"))
    refute(annotation?("T.type_template(x, y) {}"))

    refute(annotation?("C.type_template"))
    refute(annotation?("C.type_template()"))
    refute(annotation?("C.type_template(x)"))
    refute(annotation?("C.type_template(x, y)"))
    refute(annotation?("C.type_template {}"))
    refute(annotation?("C.type_template() {}"))
    refute(annotation?("C.type_template(x) {}"))
    refute(annotation?("C.type_template(x, y) {}"))
  end

  def test_unsafe
    assert(annotation?("unsafe(x)"))

    refute(annotation?("unsafe"))
    refute(annotation?("unsafe()"))
    refute(annotation?("unsafe(x, y)"))

    refute(annotation?("T.unsafe"))
    refute(annotation?("T.unsafe()"))
    refute(annotation?("T.unsafe(x)"))
    refute(annotation?("T.unsafe(x, y)"))

    refute(annotation?("C.unsafe"))
    refute(annotation?("C.unsafe()"))
    refute(annotation?("C.unsafe(x)"))
    refute(annotation?("C.unsafe(x, y)"))
  end

  def test_untyped
    assert(annotation?("T.untyped"))
    assert(annotation?("T.untyped()"))

    refute(annotation?("T.untyped(x)"))
    refute(annotation?("T.untyped(x, y)"))

    refute(annotation?("untyped"))
    refute(annotation?("untyped()"))
    refute(annotation?("untyped(x)"))
    refute(annotation?("untyped(x, y)"))

    refute(annotation?("C.untyped"))
    refute(annotation?("C.untyped()"))
    refute(annotation?("C.untyped(x)"))
    refute(annotation?("C.untyped(x, y)"))
  end

  private

  sig { params(source: String).returns(T::Boolean) }
  def annotation?(source)
    node = parse(source)

    RubyLsp::Requests::Support::Sorbet.annotation?(node)
  end

  sig do
    params(source: String)
      .returns(YARP::CallNode)
  end
  def parse(source)
    program = T.let(YARP.parse(source).value, YARP::Node)

    select_relevant_node([program])
  end

  sig do
    params(nodes: T::Array[YARP::Node]).returns(YARP::CallNode)
  end
  def select_relevant_node(nodes)
    nodes.each do |node|
      case node
      when YARP::CallNode
        return node
      end
    end

    select_relevant_node(nodes.map(&:child_nodes).flatten.compact)
  end
end
