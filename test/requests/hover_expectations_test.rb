# typed: true
# frozen_string_literal: true

require "test_helper"
require "net/http" # for stubbing
require "expectations/expectations_test_runner"

class HoverExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Hover, "hover"

  def assert_expectations(source, expected)
    source = substitute(source)
    actual = T.cast(run_expectations(source), T.nilable(LanguageServer::Protocol::Interface::Hover))
    actual_json = actual ? JSON.parse(actual.to_json) : nil
    assert_equal(json_expectations(substitute(expected)), actual_json)
  end

  def test_search_index_being_nil
    store = RubyLsp::Store.new
    store.set(uri: "file:///fake.rb", source: "belongs_to :foo", version: 1)

    RubyLsp::Requests::Support::RailsDocumentClient.stubs(search_index: nil)
    RubyLsp::Executor.new(store).execute({
      method: "textDocument/hover",
      params: { textDocument: { uri: "file:///fake.rb" }, position: { line: 0, character: 0 } },
    }).response
  end

  class FakeHTTPResponse
    attr_reader :code, :body

    def initialize(code, body)
      @code = code
      @body = body
    end
  end

  def run_expectations(source)
    js_content = File.read(File.join(TEST_FIXTURES_DIR, "rails_search_index.js"))
    fake_response = FakeHTTPResponse.new("200", js_content)

    position = @__params&.first || { character: 0, line: 0 }

    Net::HTTP.stubs(get_response: fake_response)
    store = RubyLsp::Store.new
    store.set(uri: "file:///fake.rb", source: source, version: 1)

    RubyLsp::Executor.new(store).execute({
      method: "textDocument/hover",
      params: { textDocument: { uri: "file:///fake.rb" }, position: position },
    }).response
  end

  private

  def substitute(original)
    original.gsub("RAILTIES_VERSION", Gem::Specification.find_by_name("railties").version.to_s)
  end
end
