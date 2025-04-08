# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class MinitestTestRunnerTest < Minitest::Test
    def test_minitest_output
      plugin_path = "lib/ruby_lsp/ruby_lsp_reporter_plugin.rb"
      # In Ruby 3.1, the require fails unless Bundler is set up.
      env = { "RUBYOPT" => "-rbundler/setup -r./#{plugin_path}", "RUBY_LSP_TEST_RUNNER" => "run" }
      _stdin, stdout, _stderr, _wait_thr =
        Open3 #: as untyped
          .popen3(
            env,
            "bundle",
            "exec",
            "ruby",
            "-Itest",
            "test/fixtures/minitest_example.rb",
          )

      stdout.binmode
      stdout.sync = true

      actual = parse_json_api_stream(stdout)

      uri = URI::Generic.from_path(path: "#{Dir.pwd}/test/fixtures/minitest_example.rb").to_s
      expected = [
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_fails",
            "uri" => uri,
          },
        },
        {
          "method" => "fail",
          "params" => {
            "id" => "SampleTest#test_that_fails",
            "message" => "Expected: 1\n  Actual: 2",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_is_pending",
            "uri" => uri,
          },
        },
        {
          "method" => "skip",
          "params" => {
            "id" => "SampleTest#test_that_is_pending",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_passes",
            "uri" => uri,
          },
        },
        {
          "method" => "pass",
          "params" => {
            "id" => "SampleTest#test_that_passes",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_that_raises",
            "uri" => uri,
          },
        },
        {
          "method" => "error",
          "params" => {
            "id" => "SampleTest#test_that_raises",
            "message" => "RuntimeError: oops\n    test/fixtures/minitest_example.rb:24:in #{error_location}",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "SampleTest#test_with_output",
            "uri" => uri,
          },
        },
        {
          "method" => "append_output",
          "params" => {
            "message" => "hello from $stdout.puts\r\nanother line\r\n",
          },
        },
        {
          "method" => "append_output",
          "params" => {
            "message" => "hello from puts\r\nanother line\r\n",
          },
        },
        {
          "method" => "append_output",
          "params" => {
            "message" => "hello from write\r\nanother line",
          },
        },
        {
          "method" => "pass",
          "params" => {
            "id" => "SampleTest#test_with_output",
            "uri" => uri,
          },
        },
      ]

      expected.each do |message|
        assert_includes(actual, message)
      end
    end

    private

    def error_location
      ruby_version = Gem::Version.new(RUBY_VERSION)

      if ruby_version >= Gem::Version.new("3.4")
        "'SampleTest#test_that_raises'"
      else
        "`test_that_raises'"
      end
    end
  end
end
