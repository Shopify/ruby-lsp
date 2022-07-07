# typed: true
# frozen_string_literal: true

require "test_helper"

class FormattingTest < Minitest::Test
  def setup
    @document = RubyLsp::Document.new(+<<~RUBY)
      class Foo
      def foo
      end
      end
    RUBY
  end

  def test_formats_with_rubocop_when_present
    assert_equal(<<~RUBY, formatted_document)
      # typed: true
      # frozen_string_literal: true

      class Foo
        def foo
        end
      end
    RUBY
  end

  def test_formats_with_syntax_tree_when_rubocop_is_not_present
    with_uninstalled_rubocop do
      assert_equal(<<~RUBY, formatted_document)
        class Foo
          def foo
          end
        end
      RUBY
    end
  end

  private

  def with_uninstalled_rubocop(&block)
    rubocop_paths = $LOAD_PATH.select { |path| path.include?("gems/rubocop") }
    rubocop_paths.each { |path| $LOAD_PATH.delete(path) }
    $LOADED_FEATURES.delete_if { |path| path.include?("ruby_lsp/requests") || path.include?("gems/rubocop") }
    unload_constants

    block.call
  ensure
    $LOAD_PATH.unshift(*rubocop_paths)
    $LOADED_FEATURES.delete_if { |path| path.include?("ruby_lsp/requests") }
    RubyLsp.send(:remove_const, :Requests)
    require "ruby_lsp/requests"
  end

  def unload_constants
    RubyLsp.send(:remove_const, :Requests)
    Object.send(:remove_const, :RuboCop)
  rescue NameError
    # Constants are already unloaded
  end

  def formatted_document
    require "ruby_lsp/requests"
    RubyLsp::Requests::Formatting.new("file://#{__FILE__}", @document).run&.first&.new_text
  end
end
