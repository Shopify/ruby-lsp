# typed: true
# frozen_string_literal: true

require "test_helper"

class FormattingTest < Minitest::Test
  def setup
    @global_state = RubyLsp::GlobalState.new
    @global_state.formatter = "rubocop"
    @global_state.register_formatter(
      "rubocop",
      RubyLsp::Requests::Support::RuboCopFormatter.instance,
    )
    @global_state.register_formatter(
      "syntax_tree",
      RubyLsp::Requests::Support::SyntaxTreeFormatter.instance,
    )
    @document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI::Generic.from_path(path: __FILE__))
      class Foo
      def foo
      end
      end
    RUBY
  end

  def test_formats_with_rubocop
    assert_equal(<<~RUBY, formatted_document("rubocop"))
      # typed: true
      # frozen_string_literal: true

      class Foo
        def foo
        end
      end
    RUBY
  end

  def test_formats_with_syntax_tree
    assert_equal(<<~RUBY, formatted_document("syntax_tree"))
      class Foo
        def foo
        end
      end
    RUBY
  end

  def test_does_not_format_with_formatter_is_none
    original_formatter = @global_state.formatter
    @global_state.formatter = "none"
    document = RubyLsp::RubyDocument.new(source: "def foo", version: 1, uri: URI::Generic.from_path(path: __FILE__))
    assert_nil(RubyLsp::Requests::Formatting.new(@global_state, document).perform)
  ensure
    @global_state.formatter = original_formatter
  end

  def test_syntax_tree_formatting_uses_options_from_streerc
    config_contents = <<~TXT
      --print-width=100
      --plugins=plugin/trailing_comma
    TXT

    with_syntax_tree_config_file(config_contents) do
      @document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI::Generic.from_path(path: __FILE__))
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
    require "ruby_lsp/requests"
    @global_state.formatter = "syntax_tree"
    document = RubyLsp::RubyDocument.new(source: "def foo", version: 1, uri: URI::Generic.from_path(path: __FILE__))
    assert_nil(RubyLsp::Requests::Formatting.new(@global_state, document).perform)
  end

  def test_syntax_tree_formatting_returns_nil_if_file_matches_ignore_files_options_from_streerc
    config_contents = <<~TXT
      --ignore-files=#{Pathname.new(__FILE__).relative_path_from(Dir.pwd)}
    TXT

    with_syntax_tree_config_file(config_contents) do
      @document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI::Generic.from_path(path: __FILE__))
        class Foo
        def foo
        end
        end
      RUBY
      assert_nil(formatted_document("syntax_tree"))
    end
  end

  def test_rubocop_formatting_ignores_syntax_invalid_documents
    document = RubyLsp::RubyDocument.new(source: "def foo", version: 1, uri: URI::Generic.from_path(path: __FILE__))
    assert_nil(RubyLsp::Requests::Formatting.new(@global_state, document).perform)
  end

  def test_returns_nil_if_document_is_already_formatted
    document = RubyLsp::RubyDocument.new(source: +<<~RUBY, version: 1, uri: URI::Generic.from_path(path: __FILE__))
      # typed: strict
      # frozen_string_literal: true

      class Foo
        def foo
        end
      end
    RUBY
    assert_nil(RubyLsp::Requests::Formatting.new(@global_state, document).perform)
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

  def test_returns_nil_when_formatter_is_invalid
    assert_nil(formatted_document("invalid"))
  end

  def test_using_a_custom_formatter
    require "singleton"
    formatter_class = Class.new do
      include Singleton
      include RubyLsp::Requests::Support::Formatter

      def run_formatting(uri, document)
        "#{document.source}\n# formatter by my-custom-formatter"
      end
    end

    @global_state.register_formatter("my-custom-formatter", T.unsafe(formatter_class).instance)
    assert_includes(formatted_document("my-custom-formatter"), "# formatter by my-custom-formatter")
  end

  def test_returns_nil_when_formatter_is_none
    assert_nil(formatted_document("none"))
  end

  private

  def formatted_document(formatter)
    require "ruby_lsp/requests"
    @global_state.formatter = formatter
    RubyLsp::Requests::Formatting.new(@global_state, @document).perform&.first&.new_text
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
    return unless defined?(RubyLsp::Requests::Support::SyntaxTreeFormatter)

    Singleton.__init__(RubyLsp::Requests::Support::SyntaxTreeFormatter)
    @global_state.register_formatter(
      "syntax_tree",
      RubyLsp::Requests::Support::SyntaxTreeFormatter.instance,
    )
  end
end
