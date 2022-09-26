# typed: true
# frozen_string_literal: true

require "test_helper"
require "expectations/expectations_test_runner"

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

  class FakeHTTPResponse
    attr_reader :code, :body

    def initialize(code, body)
      @code = code
      @body = body
    end
  end

  def run_expectations(source)
    document = RubyLsp::Document.new(source)
    js_content = File.read(File.join(TEST_FIXTURES_DIR, "rails_search_index.js"))
    fake_response = FakeHTTPResponse.new("200", js_content)
    Net::HTTP.stub(:get_response, fake_response) do
      RubyLsp::Requests::DocumentLink.new(@_path, document).run
    end
  end

  private

  def substitute(original)
    substitute_railties_version(substitute_syntax_tree_version(original))
      .sub("BUNDLER_PATH", Bundler.bundle_path.to_s)
      .sub("RUBY_ROOT", RbConfig::CONFIG["rubylibdir"])
  end

  def substitute_syntax_tree_version(original)
    original.sub("SYNTAX_TREE_VERSION", Gem::Specification.find_by_name("syntax_tree").version.to_s)
  end

  def substitute_railties_version(original)
    original.sub("RAILTIES_VERSION", Gem::Specification.find_by_name("railties").version.to_s)
  end
end
