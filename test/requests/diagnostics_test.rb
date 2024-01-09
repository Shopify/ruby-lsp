# typed: true
# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/requests/support/rubocop_diagnostics_runner"

class DiagnosticsTest < Minitest::Test
  def test_empty_diagnostics_for_ignored_file
    fixture_path = File.expand_path("../fixtures/def_multiline_params.rb", __dir__)
    document = RubyLsp::RubyDocument.new(
      source: File.read(fixture_path),
      version: 1,
      uri: URI::Generic.from_path(path: fixture_path),
    )

    result = RubyLsp::Requests::Diagnostics.new(document).response
    assert_empty(result)
  end

  def test_returns_syntax_error_diagnostics
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///fake/file.rb"))
      def foo
    RUBY

    diagnostics = T.must(RubyLsp::Requests::Diagnostics.new(document).response)

    assert_equal(2, diagnostics.length)
    assert_equal("expected an `end` to close the `def` statement", T.must(diagnostics.last).message)
  end

  def test_empty_diagnostics_without_rubocop
    document = RubyLsp::RubyDocument.new(source: <<~RUBY, version: 1, uri: URI("file:///fake/file.rb"))
      def foo
        "Hello, world!"
      end
    RUBY

    klass = RubyLsp::Requests::Support::RuboCopDiagnosticsRunner
    RubyLsp::Requests::Support.send(:remove_const, :RuboCopDiagnosticsRunner)

    diagnostics = T.must(RubyLsp::Requests::Diagnostics.new(document).response)

    assert_equal(0, diagnostics.length)
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

    # Make sure the rubocop runner is loaded
    diagnostics = T.must(RubyLsp::Requests::Diagnostics.new(document).response)

    assert_operator(diagnostics.length, :>, 0)
  end
end
