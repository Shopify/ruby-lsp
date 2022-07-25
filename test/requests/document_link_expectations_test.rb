# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

class DocumentLinkExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentLink, "document_link"

  def assert_expectations(source, expected)
    actual = T.cast(run_expectations(source), T::Array[LanguageServer::Protocol::Interface::DocumentLink])
    assert_equal(map_expectations(json_expectations(expected)), JSON.parse(actual.to_json))
  end

  def map_expectations(expectations)
    expectations.each do |expectation|
      expectation["target"] = substitute(expectation["target"])
      expectation["tooltip"] = substitute(expectation["tooltip"])
    end
  end

  def substitute(original)
    original
      .sub("BUNDLER_PATH", Bundler.bundle_path.to_s)
      .sub("SYNTAX_TREE_VERSION", Gem::Specification.find_by_name("syntax_tree").version.to_s)
      .sub("RUBY_ROOT", RbConfig::CONFIG["rubylibdir"])
  end
end
