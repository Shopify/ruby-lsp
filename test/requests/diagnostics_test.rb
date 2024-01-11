# typed: true
# frozen_string_literal: true

require "test_helper"

class DiagnosticsTest < Minitest::Test
  def test_empty_diagnostics_for_ignored_file
    fixture_path = File.expand_path("../fixtures/def_multiline_params.rb", __dir__)
    document = RubyLsp::RubyDocument.new(
      source: File.read(fixture_path),
      version: 1,
      uri: URI::Generic.from_path(path: fixture_path),
    )

    result = RubyLsp::Requests::Diagnostics.new(document).perform
    assert_empty(result)
  end

  def test_returns_syntax_error_diagnostics
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///fake/file.rb"))
      def foo
    RUBY

    diagnostics = T.must(RubyLsp::Requests::Diagnostics.new(document).perform)

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
    require "ruby_lsp/requests/support/rubocop_diagnostics_runner"
    klass = RubyLsp::Requests::Support::RuboCopDiagnosticsRunner
    RubyLsp::Requests::Support.send(:remove_const, :RuboCopDiagnosticsRunner)

    diagnostics = T.must(RubyLsp::Requests::Diagnostics.new(document).perform)

    assert_empty(diagnostics)
  ensure
    # Restore the class
    RubyLsp::Requests::Support.const_set(:RuboCopDiagnosticsRunner, klass)
  end

  def test_empty_diagnostics_with_rubocop
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///fake/file.rb"))
      def foo
        "Hello, world!"
      end
    RUBY

    diagnostics = T.must(RubyLsp::Requests::Diagnostics.new(document).perform)

    refute_empty(diagnostics)
  end
end
