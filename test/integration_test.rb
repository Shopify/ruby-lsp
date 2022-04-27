# frozen_string_literal: true

require "test_helper"
require "open3"
require "timeout"

# Important integration test notes
#
# 1. If the request returns `nil`, use `send_request` and do not try to read the response or else we hang reading from
# stdout
# 2. Make sure the request name is exactly the expected in CLI (e.g.: textDocument/foldingRange instead of
# textDocument/foldingRanges). If the name is incorrect, the LSP won't return anything and the test will hang trying to
# read from stdout
# 3. The goal is to verify that all parts are working together. Don't create extensive tests with long code examples -
# those are meant for unit tests
class IntegrationTest < Minitest::Test
  FEATURE_TO_PROVIDER = {
    "documentSymbols" => :documentSymbolProvider,
    "foldingRanges" => :foldingRangeProvider,
    "semanticHighlighting" => :semanticTokensProvider,
    "formatting" => :documentFormattingProvider,
    "codeActions" => :codeActionProvider,
  }.freeze

  def setup
    # Start a new Ruby LSP server in a separate process and set the IOs to binary mode
    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3("bundle exec ruby-lsp")
  end

  def teardown
    # Tell the LSP to shutdown
    make_request("shutdown")

    # Make sure IOs are closed
    @stdin.close
    @stdout.close
    @stderr.close

    # Make sure the exit status is zero
    assert_equal(0, @wait_thr.value)
  end

  def test_document_symbol
    initialize_lsp(["documentSymbols"])

    response = make_request("textDocument/documentSymbol", { textDocument: { uri: "file://#{__FILE__}" } })
    symbol = response.first
    assert_equal("Foo", symbol[:name])
    assert_equal(RubyLsp::Requests::DocumentSymbol::SYMBOL_KIND[:class], symbol[:kind])
  end

  def test_semantic_highlighting
    initialize_lsp(["semanticHighlighting"])

    response = make_request("textDocument/semanticTokens/full", { textDocument: { uri: "file://#{__FILE__}" } })
    assert_empty(response[:data])
  end

  def test_formatting
    initialize_lsp(["formatting"])

    response = make_request("textDocument/formatting", { textDocument: { uri: "file://#{__FILE__}" } })
    assert_equal(<<~FORMATTED, response.first[:newText])
      # frozen_string_literal: true

      class Foo
      end
    FORMATTED
  end

  def test_code_actions
    initialize_lsp(["codeActions"])

    response = make_request("textDocument/codeAction",
      { textDocument: { uri: "file://#{__FILE__}" }, range: { start: { line: 0 }, end: { line: 1 } } })
    quickfix = response.first
    assert_equal("quickfix", quickfix[:kind])
    assert_match(%r{Autocorrect .*/.*}, quickfix[:title])
  end

  def test_document_did_close
    initialize_lsp([])
    assert(send_request("textDocument/didClose", { textDocument: { uri: "file://#{__FILE__}" } }))
  end

  def test_document_did_change
    initialize_lsp([])
    assert(send_request(
      "textDocument/didChange",
      {
        textDocument: { uri: "file://#{__FILE__}" },
        contentChanges: [{
          text: "class Foo\ndef bar\nend\nend",
          range: { start: { line: 0, character: 0 }, end: { line: 1, character: 3 } },
        }],
      }
    ))
  end

  def test_folding_ranges
    initialize_lsp(["foldingRanges"])

    response = make_request("textDocument/foldingRange", { textDocument: { uri: "file://#{__FILE__}" } })
    assert_equal({ startLine: 0, endLine: 1, kind: "region" }, response.first)
  end

  private

  def make_request(request, params = nil)
    send_request(request, params)

    Timeout.timeout(5) do
      # Read headers until line breaks
      headers = @stdout.gets("\r\n\r\n")
      # Read the response content based on the length received in the headers
      raw_response = @stdout.read(headers[/Content-Length: (\d+)/i, 1].to_i)
      JSON.parse(raw_response, symbolize_names: true)[:result]
    end
  rescue Timeout::Error
    raise "Request #{request} timed out. Is the request returning a response?"
  end

  def send_request(request, params = nil)
    hash = {
      jsonrpc: "2.0",
      id: rand(100),
      method: request,
    }

    hash[:params] = params if params
    json = hash.to_json
    @stdin.write("Content-Length: #{json.length}\r\n\r\n#{json}")
  end

  def initialize_lsp(enabled_features)
    response = make_request(
      "initialize",
      {
        initializationOptions: {
          enabledFeatures: enabled_features,
        },
      }
    )

    assert(true, response.dig(:capabilities, :textDocumentSync, :openClose))
    assert(
      LanguageServer::Protocol::Constant::TextDocumentSyncKind::INCREMENTAL,
      response.dig(:capabilities, :textDocumentSync, :openClose)
    )

    enabled_features.each do |feature|
      assert(response.dig(:capabilities, FEATURE_TO_PROVIDER[feature]))
    end

    enabled_providers = enabled_features.map { |feature| FEATURE_TO_PROVIDER[feature] }
    assert_equal([:textDocumentSync, *enabled_providers], response[:capabilities].keys)

    # Open a document to serve as a base for all requests
    make_request("textDocument/didOpen", { textDocument: { uri: "file://#{__FILE__}", text: "class Foo\nend" } })
  end
end
