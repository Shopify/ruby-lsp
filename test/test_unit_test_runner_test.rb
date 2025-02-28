# typed: true
# frozen_string_literal: true

require "test_helper"
require "stringio"

module RubyLsp
  class TestUnitTestRunnerTest < Minitest::Test
    def test_test_runner_output
      _stdin, stdout, _stderr, _wait_thr = Open3.popen3(
        "bundle",
        "exec",
        "ruby",
        "test/fixtures/test_unit_example.rb",
        "--runner",
        "ruby_lsp",
      )
      stdout.binmode
      stdout.sync = true

      actual = parse_output(stdout)

      uri = URI::Generic.from_path(path: "#{Dir.pwd}/test/fixtures/test_unit_example.rb").to_s
      expected = [
        {
          "method" => "start",
          "params" => {
            "id" => "Sample#test_that_fails",
            "uri" => uri,
          },
        },
        {
          "method" => "fail",
          "params" => {
            "id" => "Sample#test_that_fails",
            "message" => "<1> expected but was\n<2>.",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "Sample#test_that_is_pending",
            "uri" => uri,
          },
        },
        {
          "method" => "skip",
          "params" => {
            "id" => "Sample#test_that_is_pending",
            "message" => "pending test",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "Sample#test_that_passes",
            "uri" => uri,
          },
        },
        {
          "method" => "pass",
          "params" => {
            "id" => "Sample#test_that_passes",
            "uri" => uri,
          },
        },
        {
          "method" => "start",
          "params" => {
            "id" => "Sample#test_that_raises",
            "uri" => uri,
          },
        },
        {
          "method" => "error",
          "params" => {
            "id" => "Sample#test_that_raises",
            "message" => "RuntimeError: oops",
            "uri" => uri,
          },
        },
      ]
      assert_equal(expected, actual)
    end

    private

    def parse_output(output)
      result = []
      while (headers = output.gets("\r\n\r\n"))
        content_length = headers[/Content-Length: (\d+)/i, 1]
        data = output.read(Integer(content_length))
        json = JSON.parse(T.must(data))
        result << json
      end
      result
    end
  end
end
