# typed: true
# frozen_string_literal: true

require "test_helper"
require "open3"
require "timeout"

# Important integration test notes
#
# 1. If the request returns `nil`, use `send_request` and do not try to read the response or else it times out
# 2. Make sure the request name is exactly the expected in CLI (e.g.: textDocument/foldingRange instead of
# textDocument/foldingRanges). If the name is incorrect, the LSP won't return anything reading the response will timeout
# 3. The goal is to verify that all parts are working together. Don't create extensive tests with long code examples -
# those are meant for unit tests
class IntegrationTest < Minitest::Test
  FEATURE_TO_PROVIDER = {
    "documentHighlights" => :documentHighlightProvider,
    "documentLink" => :documentLinkProvider,
    "documentSymbols" => :documentSymbolProvider,
    "foldingRanges" => :foldingRangeProvider,
    "selectionRanges" => :selectionRangeProvider,
    "semanticHighlighting" => :semanticTokensProvider,
    "formatting" => :documentFormattingProvider,
    "onTypeFormatting" => :documentOnTypeFormattingProvider,
    "codeActions" => :codeActionProvider,
    "diagnostics" => :diagnosticProvider,
    "hover" => :hoverProvider,
    "codeLens" => :codeLensProvider,
    "definition" => :definitionProvider,
    "workspaceSymbol" => :workspaceSymbolProvider,
  }.freeze

  def setup
    # Start a new Ruby LSP server in a separate process and set the IOs to binary mode
    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3("bundle exec ruby-lsp")
    @stdin.binmode
    @stdout.binmode

    @uri = URI::Generic.from_path(path: __FILE__)
  end

  def teardown
    # Tell the LSP to shutdown
    make_request("shutdown")
    send_request("exit")

    if @wait_thr.value != 0
      # If the process didn't exit cleanly, print the stderr
      $stderr.puts(@stderr.read)
    end

    # Make sure IOs are closed
    @stdin.close
    @stdout.close
    @stderr.close

    # Make sure the exit status is zero
    assert_equal(0, @wait_thr.value)
    refute_predicate(@wait_thr, :alive?)
  end

  def test_code_action_resolve
    initialize_lsp(["codeActions"])
    open_file_with("class Foo\nend")

    response = make_request(
      "codeAction/resolve",
      {
        kind: "refactor.extract",
        data: {
          range: { start: { line: 1, character: 1 }, end: { line: 1, character: 3 } },
          uri: @uri,
        },
      },
    )
    assert_equal("Refactor: Extract Variable", response[:result][:title])
  end

  private

  def make_request(request, params = nil)
    send_request(request, params)
    read_response(request)
  end

  def read_response(request)
    timeout_amount = ENV["CI"] ? 20 : 5

    Timeout.timeout(timeout_amount) do
      # Read headers until line breaks
      headers = @stdout.gets("\r\n\r\n")
      # Read the response content based on the length received in the headers
      raw_response = @stdout.read(headers[/Content-Length: (\d+)/i, 1].to_i)
      JSON.parse(raw_response, symbolize_names: true)
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

  def initialize_lsp(enabled_features, experimental_features_enabled: false)
    response = make_request(
      "initialize",
      {
        initializationOptions: {
          enabledFeatures: enabled_features,
          experimentalFeaturesEnabled: experimental_features_enabled,
          formatter: "rubocop",
        },
        capabilities: {
          window: { workDoneProgress: false },
        },
      },
    )

    assert_nil(response[:error])

    response = response[:result]

    assert(true, response.dig(:capabilities, :textDocumentSync, :openClose))
    assert(
      LanguageServer::Protocol::Constant::TextDocumentSyncKind::INCREMENTAL,
      response.dig(:capabilities, :textDocumentSync, :openClose),
    )

    enabled_features.each do |feature|
      assert(response.dig(:capabilities, FEATURE_TO_PROVIDER[feature]))
    end

    enabled_providers = enabled_features.map { |feature| FEATURE_TO_PROVIDER[feature] }
    assert_equal([:positionEncoding, :textDocumentSync, *enabled_providers], response[:capabilities].keys)
  end

  def open_file_with(content)
    send_request("textDocument/didOpen", { textDocument: { uri: @uri, text: content } })
  end
end
