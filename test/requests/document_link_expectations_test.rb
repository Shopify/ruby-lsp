# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DocumentLinkExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentLink, "document_link"

  def assert_expectations(source, expected)
    actual = run_expectations(source)
    assert_equal(map_expectations(json_expectations(expected)), JSON.parse(actual.to_json))
  end

  def map_expectations(expectations)
    expectations.each do |expectation|
      expectation["target"] = expectation["target"].sub("BUNDLER_PATH", Bundler.bundle_path.to_s)
    end
  end
end
