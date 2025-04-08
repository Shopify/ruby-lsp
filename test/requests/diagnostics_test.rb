# typed: true
# frozen_string_literal: true

require "test_helper"

class DiagnosticsTest < Minitest::Test
  def setup
    @uri = URI("file:///fake/file.rb")
    @global_state = RubyLsp::GlobalState.new
    @global_state.apply_options({
      initializationOptions: { linters: ["rubocop_internal"] },
    })
    @global_state.register_formatter(
      "rubocop_internal",
      RubyLsp::Requests::Support::RuboCopFormatter.new,
    )
  end

  def test_empty_diagnostics_for_ignored_file
    fixture_path = File.expand_path("../fixtures/def_multiline_params.rb", __dir__)
    document = RubyLsp::RubyDocument.new(
      source: File.read(fixture_path),
      version: 1,
      uri: URI::Generic.from_path(path: fixture_path),
      global_state: @global_state,
    )

    result = RubyLsp::Requests::Diagnostics.new(@global_state, document).perform
    assert_empty(result)
  end

  def test_returns_syntax_error_diagnostics
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: @uri, global_state: @global_state)
      def foo
    RUBY

    diagnostics = RubyLsp::Requests::Diagnostics.new(@global_state, document).perform #: as !nil

    assert_equal(2, diagnostics.length)
    assert_equal("expected an `end` to close the `def` statement", T.must(diagnostics.last).message)
  end

  def test_empty_diagnostics_without_rubocop
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: @uri, global_state: @global_state)
      def foo
        "Hello, world!"
      end
    RUBY

    # We want to unload the rubocop runner for this test; first make sure that it's loaded
    require "ruby_lsp/requests/support/rubocop_formatter"
    klass = RubyLsp::Requests::Support::RuboCopFormatter
    RubyLsp::Requests::Support.send(:remove_const, :RuboCopFormatter)

    @global_state.instance_variable_get(:@supported_formatters).delete("rubocop_internal")

    diagnostics = RubyLsp::Requests::Diagnostics.new(@global_state, document).perform #: as !nil

    assert_empty(diagnostics)
  ensure
    # Restore the class
    RubyLsp::Requests::Support.const_set(:RuboCopFormatter, klass)
  end

  def test_empty_diagnostics_with_rubocop
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: @uri, global_state: @global_state)
      def foo
        "Hello, world!"
      end
    RUBY

    diagnostics = RubyLsp::Requests::Diagnostics.new(@global_state, document).perform #: as !nil

    refute_empty(diagnostics)
  end

  def test_registering_formatter_with_diagnostic_support
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: @uri, global_state: @global_state)
      def foo
        "Hello, world!"
      end
    RUBY

    formatter_class = Class.new do
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

    @global_state.register_formatter("my-custom-formatter", formatter_class.new)
    @global_state.apply_options({
      initializationOptions: { linters: ["my-custom-formatter"] },
    })

    diagnostics = RubyLsp::Requests::Diagnostics.new(@global_state, document).perform #: as !nil
    assert(diagnostics.find { |d| d.message == "Hello from custom formatter" })
  end

  def test_ambiguous_syntax_warnings
    document = RubyLsp::RubyDocument.new(source: <<~RUBY.chomp, version: 1, uri: @uri, global_state: @global_state)
      b +a
      b -a
      b *a
      b /a/
    RUBY

    diagnostics = RubyLsp::Requests::Diagnostics.new(@global_state, document).perform #: as !nil
    assert_match("ambiguous first argument", T.must(diagnostics[0]).message)
    assert_match("ambiguous first argument", T.must(diagnostics[1]).message)
    assert_match("ambiguous `*`", T.must(diagnostics[2]).message)
    assert_match("ambiguous `/`", T.must(diagnostics[3]).message)
  end

  def test_END_inside_method_definition_warning
    document = RubyLsp::RubyDocument.new(source: <<~RUBY.chomp, version: 1, uri: @uri, global_state: @global_state)
      def m; END{}; end
    RUBY

    diagnostics = RubyLsp::Requests::Diagnostics.new(@global_state, document).perform #: as !nil
    assert_equal("END in method; use at_exit", T.must(diagnostics[0]).message)
  end

  def test_syntax_error_diagnostic
    document = RubyLsp::RubyDocument.new(source: <<~RUBY.chomp, version: 1, uri: @uri, global_state: @global_state)
      def foo
    RUBY

    diagnostics = RubyLsp::Requests::Diagnostics.new(@global_state, document).perform #: as !nil
    assert_equal("expected a delimiter to close the parameters", T.must(diagnostics[0]).message)
    assert_equal(
      "unexpected end-of-input, assuming it is closing the parent top level context",
      T.must(diagnostics[1]).message,
    )
  end
end
