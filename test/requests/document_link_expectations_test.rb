# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "support/expectations_test_runner"

class DocumentLinkExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::DocumentLink, "document_link"

  def assert_expectations(source, expected)
    source = substitute_syntax_tree_version(source)
    actual = run_expectations(source) #: as Array[LanguageServer::Protocol::Interface::DocumentLink]
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
    dispatcher.dispatch(document.ast)
    listener.perform
  end

  def test_magic_source_links_on_unsaved_files
    source = <<~RUBY
      # source://erb/#1
      def bar
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/documentLink",
        params: { textDocument: { uri: uri } },
      )

      server.pop_response
      assert_empty(server.pop_response.response)
    end
  end

  def test_magic_source_links_with_invalid_uris
    source = <<~RUBY
      # source://some_file /#123
      def bar
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/documentLink",
        params: { textDocument: { uri: uri } },
      )

      server.pop_response
      assert_empty(server.pop_response.response)
    end
  end

  def test_package_url_links
    source = <<~RUBY
      # pkg:gem/erb#:99
      def bar
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/documentLink",
        params: { textDocument: { uri: uri } },
      )

      server.pop_response
      assert_empty(server.pop_response.response)
    end
  end

  def test_package_url_links_with_invalid_uris
    source = <<~RUBY
      # pkg:gem/rubocop$1.78.0#:99
      def bar
      end
    RUBY

    with_server(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/documentLink",
        params: { textDocument: { uri: uri } },
      )

      server.pop_response
      assert_empty(server.pop_response.response)
    end
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
