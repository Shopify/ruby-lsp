# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/documentation_visitor"

class DocumentationVisitorTest < Minitest::Test
  def test_gathering_documentation
    visitor = visit_documentation(<<~RUBY)
      # frozen_string_literal: true

      module RubyLsp
        module Requests
          # # FakeRequest
          #
          # Here's my documentation for the fake request
          class FakeRequest < Visitor
          end
        end
      end
    RUBY

    assert_equal("FakeRequest", visitor.request_name)
    assert_equal(<<~DOCUMENTATION.chomp, visitor.content)
      # FakeRequest

      Here's my documentation for the fake request
    DOCUMENTATION
  end

  def test_empty_documentation_request
    visitor = visit_documentation(<<~RUBY)
      # frozen_string_literal: true

      module RubyLsp
        module Requests
          class FakeRequest < Visitor
          end
        end
      end
    RUBY

    assert_equal("FakeRequest", visitor.request_name)
    assert_empty(visitor.content)
    assert_empty(visitor.documentation)
  end

  def test_non_request_classes
    visitor = visit_documentation(<<~RUBY)
      # frozen_string_literal: true

      module RubyLsp
        module SomeOtherThing
          class FakeRequest < Visitor
          end
        end
      end
    RUBY

    assert_nil(visitor.request_name)
    assert_nil(visitor.content)
    assert_empty(visitor.documentation)
  end

  def test_skipped_documentation
    visitor = visit_documentation(<<~RUBY)
      # frozen_string_literal: true

      module RubyLsp
        module Requests
          # :nodoc:
          class FakeRequest < Visitor
          end
        end
      end
    RUBY

    assert_predicate(visitor, :documentation_skipped?)
  end

  private

  def visit_documentation(source)
    visitor = RubyLsp::DocumentationVisitor.new
    tree = SyntaxTree.parse(source)
    visitor.visit(tree)
    visitor
  end
end
