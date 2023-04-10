# typed: true
# frozen_string_literal: true

require "test_helper"

class FormattingTest < Minitest::Test
  def setup
    @document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file://#{__FILE__}")
      class Foo
      def foo
      end
      end
    RUBY
  end

  def test_formats_with_rubocop_when_present_and_syntax_tree_not_present
    stub_syntax_tree(present: false)

    assert_equal(<<~RUBY, formatted_document)
      # typed: true
      # frozen_string_literal: true

      class Foo
        def foo
        end
      end
    RUBY
  end

  def test_formats_with_syntax_tree_when_present_and_rubocop_not_present
    stub_syntax_tree(present: true)

    with_uninstalled_rubocop do
      assert_equal(<<~RUBY, formatted_document)
        class Foo
          def foo
          end
        end
      RUBY
    end
  end

  def test_formats_with_rubocop_when_present_and_syntax_tree_also_present
    stub_syntax_tree(present: true)

    assert_equal(<<~RUBY, formatted_document)
      # typed: true
      # frozen_string_literal: true

      class Foo
        def foo
        end
      end
    RUBY
  end

  def test_does_not_format_with_neither_syntax_tree_nor_rubocop_are_present
    stub_syntax_tree(present: false)

    with_uninstalled_rubocop do
      assert_nil(formatted_document)
    end
  end

  def test_syntax_tree_formatting_uses_options_from_streerc
    config_contents = <<~TXT
      --print-width=100
      --plugins=plugin/trailing_comma
    TXT

    with_syntax_tree_config_file(config_contents) do
      @document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file://#{__FILE__}")
        class Foo
        def foo
        {one: "#{"a" * 50}", two: "#{"b" * 50}"}
        SomeClass.with(arguments).and_more_methods.some_are_wordy.who_is_demeter_again?
        end
        end
      RUBY

      assert_equal(<<~RUBY, formatted_document("syntax_tree"))
        class Foo
          def foo
            {
              one: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              two: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            }
            SomeClass.with(arguments).and_more_methods.some_are_wordy.who_is_demeter_again?
          end
        end
      RUBY
    end
  end

  def test_syntax_tree_formatting_ignores_syntax_invalid_documents
    with_uninstalled_rubocop do
      require "ruby_lsp/requests"
      document = RubyLsp::Document.new(source: "def foo", version: 1, uri: "file://#{__FILE__}")
      assert_nil(RubyLsp::Requests::Formatting.new(document).run)
    end
  end

  def test_rubocop_formatting_ignores_syntax_invalid_documents
    document = RubyLsp::Document.new(source: "def foo", version: 1, uri: "file://#{__FILE__}")
    assert_nil(RubyLsp::Requests::Formatting.new(document).run)
  end

  def test_returns_nil_if_document_is_already_formatted
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file://#{__FILE__}")
      # typed: strict
      # frozen_string_literal: true

      class Foo
        def foo
        end
      end
    RUBY
    assert_nil(RubyLsp::Requests::Formatting.new(document).run)
  end

  def test_returns_nil_if_document_is_not_in_project_folder
    document = RubyLsp::Document.new(source: +<<~RUBY, version: 1, uri: "file:///fake.rb")
      class Foo
      def foo
      end
      end
    RUBY
    assert_nil(RubyLsp::Requests::Formatting.new(document).run)
  end

  def test_allows_specifying_formatter
    SyntaxTree
      .expects(:format)
      .with(
        @document.source,
        instance_of(Integer),
        has_entry(options: instance_of(SyntaxTree::Formatter::Options)),
      )
      .once
    formatted_document("syntax_tree")
  end

  def test_raises_on_invalid_formatter
    assert_raises(RubyLsp::Requests::Formatting::InvalidFormatter) do
      formatted_document("invalid")
    end
  end

  private

  def with_uninstalled_rubocop(&block)
    rubocop_paths = $LOAD_PATH.select { |path| path.include?("gems/rubocop") }
    rubocop_paths.each { |path| $LOAD_PATH.delete(path) }
    $LOADED_FEATURES.delete_if do |path|
      path.include?("ruby_lsp/requests") || path.include?("gems/rubocop") || path.include?("rubocop/cop/ruby_lsp")
    end
    unload_constants

    block.call
  ensure
    $LOAD_PATH.unshift(*rubocop_paths)
    $LOADED_FEATURES.delete_if { |path| path.include?("ruby_lsp/requests") }
    RubyLsp.send(:remove_const, :Requests)
    require "ruby_lsp/requests"
    require "rubocop/cop/ruby_lsp/use_language_server_aliases"
  end

  def unload_constants
    RubyLsp.send(:remove_const, :Requests)
    Object.send(:remove_const, :RuboCop)
  rescue NameError
    # Constants are already unloaded
  end

  def formatted_document(formatter = "auto")
    require "ruby_lsp/requests"
    RubyLsp::Requests::Formatting.new(@document, formatter: formatter).run&.first&.new_text
  end

  def with_syntax_tree_config_file(contents)
    filepath = File.join(Dir.pwd, ".streerc")
    File.write(filepath, contents)
    clear_syntax_tree_runner_singleton_instance

    yield
  ensure
    FileUtils.rm(filepath) if filepath
    clear_syntax_tree_runner_singleton_instance
  end

  def clear_syntax_tree_runner_singleton_instance
    return unless defined?(RubyLsp::Requests::Support::SyntaxTreeFormattingRunner)

    T.unsafe(Singleton).__init__(RubyLsp::Requests::Support::SyntaxTreeFormattingRunner)
  end

  def stub_syntax_tree(present:)
    result = present ? { "syntax_tree" => "..." } : {}
    Bundler.locked_gems.stubs(:dependencies).returns(result)
  end
end
