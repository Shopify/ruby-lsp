# typed: true
# frozen_string_literal: true

require "test_helper"

class DiagnosticsTest < Minitest::Test
  def setup
    @global_state = RubyLsp::GlobalState.new
    @global_state.formatter = "rubocop"
    @global_state.register_formatter(
      "rubocop",
      RubyLsp::Requests::Support::RuboCopFormatter.instance,
    )
  end

  def test_empty_diagnostics_for_ignored_file
    fixture_path = File.expand_path("../fixtures/def_multiline_params.rb", __dir__)
    document = RubyLsp::RubyDocument.new(
      source: File.read(fixture_path),
      version: 1,
      uri: URI::Generic.from_path(path: fixture_path),
    )

    result = RubyLsp::Requests::Diagnostics.new(@global_state, document).perform
    assert_empty(result)
  end

  def test_returns_syntax_error_diagnostics
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///fake/file.rb"))
      def foo
    RUBY

    diagnostics = T.must(RubyLsp::Requests::Diagnostics.new(@global_state, document).perform)

    assert_equal(2, diagnostics.length)
    assert_equal("expected an `end` to close the `def` statement", T.must(diagnostics.last).message)
  end

  def test_empty_diagnostics_without_rubocop
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///fake/file.rb"))
      def foo
        "Hello, world!"
      end
    RUBY

    # We want to unload the rubocop runner for this test; first make sure that it's loaded
    require "ruby_lsp/requests/support/rubocop_formatter"
    klass = RubyLsp::Requests::Support::RuboCopFormatter
    RubyLsp::Requests::Support.send(:remove_const, :RuboCopFormatter)

    @global_state.instance_variable_get(:@supported_formatters).delete("rubocop")

    diagnostics = T.must(RubyLsp::Requests::Diagnostics.new(@global_state, document).perform)

    assert_empty(diagnostics)
  ensure
    # Restore the class
    RubyLsp::Requests::Support.const_set(:RuboCopFormatter, klass)
  end

  def test_empty_diagnostics_with_rubocop
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///fake/file.rb"))
      def foo
        "Hello, world!"
      end
    RUBY

    diagnostics = T.must(RubyLsp::Requests::Diagnostics.new(@global_state, document).perform)

    refute_empty(diagnostics)
  end

  def test_registering_formatter_with_diagnostic_support
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///fake/file.rb"))
      def foo
        "Hello, world!"
      end
    RUBY

    formatter_class = Class.new do
      include Singleton
      include RubyLsp::Requests::Support::Formatter

      def run_diagnostic(uri, document)
        [
          RubyLsp::Interface::Diagnostic.new(
            message: "Hello from custom formatter",
            source: "Custom formatter",
            severity: RubyLsp::Constant::DiagnosticSeverity::ERROR,
            range: RubyLsp::Interface::Range.new(
              start: RubyLsp::Interface::Position.new(line: 0, character: 0),
              end: RubyLsp::Interface::Position.new(line: 2, character: 3),
            ),
          ),
        ]
      end
    end

    @global_state.register_formatter("my-custom-formatter", T.unsafe(formatter_class).instance)
    @global_state.formatter = "my-custom-formatter"

    diagnostics = T.must(RubyLsp::Requests::Diagnostics.new(@global_state, document).perform)
    assert(diagnostics.find { |d| d.message == "Hello from custom formatter" })
  end
end
