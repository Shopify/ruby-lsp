# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class CommonTest < Minitest::Test
    def test_erb_for_erb_file
      uri = URI::Generic.from_path(path: "/path/to/file.erb")
      assert(common.erb?(uri))
    end

    def test_erb_for_html_erb_file
      uri = URI::Generic.from_path(path: "/path/to/file.html.erb")
      assert(common.erb?(uri))
    end

    def test_erb_for_rhtml_file
      uri = URI::Generic.from_path(path: "/path/to/file.rhtml")
      assert(common.erb?(uri))
    end

    def test_erb_for_rhtm_file
      uri = URI::Generic.from_path(path: "/path/to/file.rhtm")
      assert(common.erb?(uri))
    end

    def test_erb_for_rb_file
      uri = URI::Generic.from_path(path: "/path/to/file.rb")
      refute(common.erb?(uri))
    end

    private

    def common
      Class.new.include(Requests::Support::Common).new
    end
  end
end
