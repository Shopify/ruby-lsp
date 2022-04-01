# frozen_string_literal: true

require "test_helper"

class FormattingTest < Minitest::Test
  def test_formatting
    original = <<~RUBY
      def foo


      puts "Hello, world!"
      end
    RUBY

    assert_formatted(original, <<~RUBY)
      # frozen_string_literal: true

      def foo
        puts "Hello, world!"
      end
    RUBY
  end

  private

  def assert_formatted(original, formatted)
    parsed_tree = RubyLsp::Store::ParsedTree.new(original)
    result = nil

    capture_io do
      result = RubyLsp::Requests::Formatting.run("file://#{__FILE__}", parsed_tree).first.new_text
    end

    assert_equal(formatted, result)
  end
end
