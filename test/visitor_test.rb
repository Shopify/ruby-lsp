# frozen_string_literal: true

require "test_helper"

class VisitorTest < Minitest::Test
  def test_can_visit_all_nodes
    visitor = RubyLsp::Visitor.new

    SyntaxTree.constants.each do |node|
      assert_respond_to(visitor, "visit_#{RubyLsp::Visitor.class_to_visit_method(node.to_s)}")
    end
  end

  def test_class_to_visit_method
    visit_method_name = RubyLsp::Visitor.class_to_visit_method(SyntaxTree::TStringEnd.name)
    assert_equal("t_string_end", visit_method_name)
  end

  def test_visit_tree
    parsed_tree = RubyLsp::Store::ParsedTree.new(<<~RUBY)
      class Foo
        def foo; end

        class Bar
          def bar; end
        end
      end

      def baz; end
    RUBY

    visitor = DummyVisitor.new
    visitor.visit(parsed_tree.tree)
    assert_equal(["Foo", "foo", "Bar", "bar", "baz"], visitor.visited_nodes)
  end

  class DummyVisitor < RubyLsp::Visitor
    attr_reader :visited_nodes

    def initialize
      super
      @visited_nodes = []
    end

    def visit_class_declaration(node)
      @visited_nodes << node.constant.constant.value
      super
    end

    def visit_def(node)
      @visited_nodes << node.name.value
    end
  end
end
