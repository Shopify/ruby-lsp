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
