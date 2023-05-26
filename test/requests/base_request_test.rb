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
end
