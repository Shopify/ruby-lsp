# typed: true
# frozen_string_literal: true

require "test_helper"
require "coverage"
require "ruby_lsp/test_reporters/lsp_reporter"

module RubyLsp
  class LspReporterTest < Minitest::Test
    def test_coverage_results_are_formatted_as_vscode_expects
      path = "/path/to/file.rb"
      Dir.expects(:pwd).returns("/path/to").at_least_once
      Coverage.expects(:result).returns({
        path => {
          lines: [1, 2, 3, nil],
          branches: {
            ["&.", 0, 2, 2, 3, 6] => { [:then, 1, 2, 2, 2, 6] => 0, [:else, 3, 3, 2, 3, 6] => 1 },
          },
        },
        "/unrelated/file.rb" => {
          lines: [1, 2, 3, nil],
          branches: {
            ["&.", 0, 2, 2, 3, 6] => { [:then, 1, 2, 2, 2, 6] => 0, [:else, 3, 3, 2, 3, 6] => 1 },
          },
        },
      })

      uri = URI::Generic.from_path(path: File.expand_path(path)).to_s

      assert_equal(
        {
          uri =>
            [
              { executed: 1, location: { line: 0, character: 0 }, branches: [] },
              { executed: 2, location: { line: 1, character: 0 }, branches: [] },
              {
                executed: 3,
                location: { line: 2, character: 0 },
                branches:
                [
                  {
                    groupingLine: 2,
                    executed: 0,
                    location:
                          { start: { line: 2, character: 2 }, end: { line: 2, character: 6 } },
                    label: "&. then",
                  },
                  {
                    groupingLine: 2,
                    executed: 1,
                    location:
                    { start: { line: 3, character: 2 }, end: { line: 3, character: 6 } },
                    label: "&. else",
                  },
                ],
              },
            ],
        },
        LspReporter.instance.gather_coverage_results,
      )
    end

    def test_shutdown_does_nothing_in_coverage_mode
      ENV["RUBY_LSP_TEST_RUNNER"] = "coverage"
      io = LspReporter.instance.instance_variable_get(:@io)
      io.expects(:close).never
      LspReporter.instance.shutdown
    ensure
      ENV.delete("RUBY_LSP_TEST_RUNNER")
    end
  end
end
