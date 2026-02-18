# typed: true
# frozen_string_literal: true

require "test_helper"
require "coverage"
require "ruby_lsp/test_reporters/lsp_reporter"

module RubyLsp
  class LspReporterTest < Minitest::Test
    def setup
      @old_port = ENV["RUBY_LSP_REPORTER_PORT"]
      @old_test_runner = ENV["RUBY_LSP_TEST_RUNNER"]
    end

    def teardown
      ENV["RUBY_LSP_REPORTER_PORT"] = @old_port
      ENV["RUBY_LSP_TEST_RUNNER"] = @old_test_runner
    end

    def test_socket_connection_failure_fallbacks_to_stringio
      ENV["RUBY_LSP_REPORTER_PORT"] = "99999"

      reporter = LspReporter.new
      io = reporter.instance_variable_get(:@io)

      assert_kind_of(StringIO, io)
    end

    def test_socket_connects_to_ipv4_server
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1].to_s

      thread = Thread.new { server.accept }

      ENV["RUBY_LSP_REPORTER_PORT"] = port
      reporter = LspReporter.new
      io = reporter.instance_variable_get(:@io)

      assert_kind_of(Socket, io)

      accepted = thread.join(1)&.value #: untyped
      accepted&.close
      io.close
      server.close
    end

    def test_socket_connects_to_ipv6_server
      server = TCPServer.new("::1", 0)
      port = server.addr[1].to_s

      thread = Thread.new { server.accept }

      ENV["RUBY_LSP_REPORTER_PORT"] = port
      reporter = LspReporter.new
      io = reporter.instance_variable_get(:@io)

      assert_kind_of(Socket, io)

      accepted = thread.join(1)&.value #: untyped
      accepted&.close
      io.close
      server.close
    end

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
        LspReporter.new.gather_coverage_results,
      )
    end

    def test_shutdown_does_nothing_in_coverage_mode
      ENV["RUBY_LSP_TEST_RUNNER"] = "coverage"
      reporter = LspReporter.new
      io = reporter.instance_variable_get(:@io)
      io.expects(:close).never
      reporter.shutdown
    ensure
      ENV.delete("RUBY_LSP_TEST_RUNNER")
    end

    def test_uri_and_line_for_with_regular_method
      uri, line = LspReporter.uri_and_line_for(method(:test_uri_and_line_for_with_regular_method))

      assert_kind_of(URI::Generic, uri)
      assert_match(/lsp_reporter_test\.rb$/, uri.to_s)
      assert_kind_of(Integer, line)
      # Line should be zero-based
      assert_operator(line, :>=, 0)
    end

    def test_uri_and_line_for_with_unbound_method
      uri, line = LspReporter.uri_and_line_for(LspReporterTest.instance_method(:test_uri_and_line_for_with_unbound_method))

      assert_kind_of(URI::Generic, uri)
      assert_match(/lsp_reporter_test\.rb$/, uri.to_s)
      assert_kind_of(Integer, line)
      assert_operator(line, :>=, 0)
    end

    def test_uri_and_line_for_with_native_method
      result = LspReporter.uri_and_line_for(method(:puts))

      assert_nil(result)
    end

    def test_uri_and_line_for_with_eval_method
      eval("def self.eval_method; end", binding, "(eval at something)")

      result = LspReporter.uri_and_line_for(method(:eval_method))

      assert_nil(result)
    end

    def test_uri_and_line_for_converts_to_zero_based_line
      # Get the actual line number where this method is defined
      _uri, line = LspReporter.uri_and_line_for(method(:test_uri_and_line_for_converts_to_zero_based_line))

      # The method definition should be on a 1-based line, but uri_and_line_for returns 0-based
      # So we verify it's not the same as what source_location returns
      _file_path, one_based_line = method(:test_uri_and_line_for_converts_to_zero_based_line).source_location

      assert_equal(one_based_line - 1, line)
    end
  end
end
