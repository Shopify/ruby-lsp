# typed: true
# frozen_string_literal: true

require "test_helper"

class BaseRequestTest < Minitest::Test
  def setup
    @document = RubyLsp::Document.new(source: <<~RUBY, version: 1, uri: "file:///foo/bar.rb")
      class Post < ActiveRecord::Base
        scope :published do
          # find posts that are published
          where(published: true)
        end
      end
    RUBY
    @request_class = Class.new(RubyLsp::Requests::BaseRequest)
    @fake_request = @request_class.new(@document)
  end

  def test_locate
    # Locate the `ActiveRecord` module (19 is the position of the `R` character)
    found, parent = @fake_request.locate(@document.tree, 19)
    assert_instance_of(SyntaxTree::Const, found)
    assert_equal("ActiveRecord", found.value)

    assert_instance_of(SyntaxTree::VarRef, parent)
    assert_equal("ActiveRecord", parent.value.value)

    # Locate the `Base` class (27 is the position of the `B` character)
    found, parent = @fake_request.locate(@document.tree, 27)
    assert_instance_of(SyntaxTree::Const, found)
    assert_equal("Base", found.value)

    assert_instance_of(SyntaxTree::ConstPathRef, parent)
    assert_equal("Base", parent.constant.value)
    assert_equal("ActiveRecord", parent.parent.value.value)

    # Locate the `where` invocation (94 is the position of the `w` character)
    found, parent = @fake_request.locate(@document.tree, 94)
    assert_instance_of(SyntaxTree::Ident, found)
    assert_equal("where", found.value)

    assert_instance_of(SyntaxTree::CallNode, parent)
  end

  # We can remove this once we drop support for Ruby 2.7
  def test_super_is_valid_on_ruby_2_7
    document = RubyLsp::Document.new(source: "", version: 1, uri: "file:///foo/bar.rb")
    semantic_highlighting = RubyLsp::Requests::SemanticHighlighting.new(
      document,
      range: nil,
      encoder: RubyLsp::Requests::Support::SemanticTokenEncoder.new,
    )
    assert_instance_of(RubyLsp::Requests::SemanticHighlighting, semantic_highlighting)
  end
end
