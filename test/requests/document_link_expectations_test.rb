# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class DocumentLinkExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentLink, "document_link"

  def assert_expectations(source, expected)
    source = substitute_syntax_tree_version(source)
    actual = T.cast(run_expectations(source), T::Array[LanguageServer::Protocol::Interface::DocumentLink])
    assert_equal(map_expectations(json_expectations(expected)), JSON.parse(actual.to_json))
  end

  def map_expectations(expectations)
    expectations.each do |expectation|
      expectation["target"] = substitute(expectation["target"])
      expectation["tooltip"] = substitute(expectation["tooltip"])
    end
  end

  def run_expectations(source)
    uri = URI("file://#{@_path}")
    document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: @global_state)

    dispatcher = Prism::Dispatcher.new
    parse_result = document.parse_result
    listener = RubyLsp::Requests::DocumentLink.new(uri, parse_result.comments, dispatcher)
    dispatcher.dispatch(parse_result.value)
    listener.perform
  end

  private

  def substitute(original)
    substitute_syntax_tree_version(original)
      .sub("BUNDLER_PATH", Bundler.bundle_path.to_s)
      .sub("RUBY_ROOT", RbConfig::CONFIG["rubylibdir"])
  end

  def substitute_syntax_tree_version(original)
    original.sub("SYNTAX_TREE_VERSION", Gem::Specification.find_by_name("syntax_tree").version.to_s)
  end
end
