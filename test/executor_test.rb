# typed: true
# frozen_string_literal: true

require "test_helper"

class ExecutorTest < Minitest::Test
  def setup
    @store = RubyLsp::Store.new
    @message_queue = Thread::Queue.new
    @executor = RubyLsp::Executor.new(@store, @message_queue)
  end

  def teardown
    @message_queue.close
  end

  def test_initialize_enabled_features_with_array
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: { enabledFeatures: ["semanticHighlighting"] },
        capabilities: { general: { positionEncodings: ["utf-8"] } },
      },
    }).response

    hash = JSON.parse(response.to_json)
    capabilities = hash["capabilities"]

    # TextSynchronization + encodings + semanticHighlighting
    assert_equal(3, capabilities.length)
    assert_includes(capabilities, "semanticTokensProvider")
  end

  def test_initialize_enabled_features_with_hash
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: { enabledFeatures: { "semanticHighlighting" => false } },
        capabilities: { general: { positionEncodings: ["utf-8"] } },
      },
    }).response

    hash = JSON.parse(response.to_json)
    capabilities = hash["capabilities"]

    # Only semantic highlighting is turned off because all others default to true when configuring with a hash
    refute_includes(capabilities, "semanticTokensProvider")
  end

  def test_initialize_enabled_features_with_no_configuration
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: { general: { positionEncodings: ["utf-8"] } },
      },
    }).response

    hash = JSON.parse(response.to_json)
    capabilities = hash["capabilities"]

    # All features are enabled by default
    assert_includes(capabilities, "semanticTokensProvider")
  end

  def test_initialize_defaults_to_utf_8_if_present
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: { general: { positionEncodings: ["utf-8", "utf-16"] } },
      },
    }).response

    hash = JSON.parse(response.to_json)

    # All features are enabled by default
    assert_includes("utf-8", hash.dig("capabilities", "positionEncoding"))
  end

  def test_initialize_uses_utf_16_if_utf_8_is_not_present
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: { general: { positionEncodings: ["utf-16"] } },
      },
    }).response

    hash = JSON.parse(response.to_json)

    # All features are enabled by default
    assert_includes("utf-16", hash.dig("capabilities", "positionEncoding"))
  end

  def test_initialize_uses_utf_16_if_no_encodings_are_specified
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: { general: { positionEncodings: [] } },
      },
    }).response

    hash = JSON.parse(response.to_json)

    # All features are enabled by default
    assert_includes("utf-16", hash.dig("capabilities", "positionEncoding"))
  end

  def test_server_info_includes_version
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: {},
      },
    }).response

    hash = JSON.parse(response.to_json)
    assert_equal(RubyLsp::VERSION, hash.dig("serverInfo", "version"))
  end

  def test_server_info_includes_formatter
    RubyLsp::DependencyDetector.instance.expects(:detected_formatter).returns("rubocop")
    response = @executor.execute({
      method: "initialize",
      params: {
        initializationOptions: {},
        capabilities: {},
      },
    }).response

    hash = JSON.parse(response.to_json)
    assert_equal("rubocop", hash.dig("formatter"))
  end

  def test_initialized_populates_index
    @executor.execute({ method: "initialized", params: {} })

    assert_equal("$/progress", @message_queue.pop.message)
    assert_equal("$/progress", @message_queue.pop.message)

    index = @executor.instance_variable_get(:@index)
    refute_empty(index.instance_variable_get(:@entries))
  end

  def test_initialized_recovers_from_indexing_failures
    RubyIndexer::Index.any_instance.expects(:index_all).once.raises(StandardError, "boom!")

    @executor.execute({ method: "initialized", params: {} })
    notification = T.must(@message_queue.pop)
    assert_equal("window/showMessage", notification.message)
    assert_equal(
      "Error while indexing: boom!",
      T.cast(notification.params, RubyLsp::Interface::ShowMessageParams).message,
    )
  end

  def test_rubocop_errors_push_window_notification
    @executor.expects(:formatting).raises(StandardError, "boom").once

    @executor.execute({
      method: "textDocument/formatting",
      params: {
        textDocument: { uri: "file:///foo.rb" },
      },
    })

    notification = T.must(@message_queue.pop)
    assert_equal("window/showMessage", notification.message)
    assert_equal(
      "Formatting error: boom",
      T.cast(notification.params, RubyLsp::Interface::ShowMessageParams).message,
    )
  end

  def test_did_close_clears_diagnostics
    uri = URI("file:///foo.rb")
    @store.set(uri: uri, source: "", version: 1)
    @executor.execute({
      method: "textDocument/didClose",
      params: {
        textDocument: { uri: uri.to_s },
      },
    })

    notification = T.must(@message_queue.pop)
    assert_equal("textDocument/publishDiagnostics", notification.message)
    assert_empty(T.cast(notification.params, RubyLsp::Interface::PublishDiagnosticsParams).diagnostics)
  ensure
    @store.delete(uri)
  end

  def test_detects_rubocop_if_direct_dependency
    stub_dependencies(rubocop: true, syntax_tree: false)
    RubyLsp::Executor.new(@store, @message_queue)
      .execute(method: "initialize", params: { initializationOptions: { formatter: "auto" } })
    assert_equal("rubocop", @store.formatter)
  end

  def test_detects_syntax_tree_if_direct_dependency
    stub_dependencies(rubocop: false, syntax_tree: true)
    RubyLsp::Executor.new(@store, @message_queue)
      .execute(method: "initialize", params: { initializationOptions: { formatter: "auto" } })
    assert_equal("syntax_tree", @store.formatter)
  end

  def test_gives_rubocop_precedence_if_syntax_tree_also_present
    stub_dependencies(rubocop: true, syntax_tree: true)
    RubyLsp::Executor.new(@store, @message_queue).send(
      :initialize_request,
      { initializationOptions: { formatter: "auto" } },
    )
    assert_equal("rubocop", @store.formatter)
  end

  def test_sets_formatter_to_none_if_neither_rubocop_or_syntax_tree_are_present
    stub_dependencies(rubocop: false, syntax_tree: false)
    RubyLsp::Executor.new(@store, @message_queue).send(
      :initialize_request,
      { initializationOptions: { formatter: "auto" } },
    )
    assert_equal("none", @store.formatter)
  end

  def test_shows_error_if_formatter_set_to_rubocop_but_rubocop_not_available
    with_uninstalled_rubocop do
      executor = RubyLsp::Executor.new(@store, @message_queue)

      executor.execute(method: "initialize", params: { initializationOptions: { formatter: "rubocop" } })
      executor.execute(method: "initialized")

      assert_equal("none", @store.formatter)
      refute_empty(@message_queue)

      # Account for starting and ending the progress notifications during initialized
      assert_equal("window/workDoneProgress/create", @message_queue.pop.message)
      assert_equal("$/progress", @message_queue.pop.message)

      notification = T.must(@message_queue.pop)
      assert_equal("window/showMessage", notification.message)
      assert_equal(
        "Ruby LSP formatter is set to `rubocop` but RuboCop was not found in the Gemfile or gemspec.",
        T.cast(notification.params, RubyLsp::Interface::ShowMessageParams).message,
      )
    end
  end

  def test_returns_void_for_unhandled_request
    executor = RubyLsp::Executor.new(@store, @message_queue)

    result = executor.execute(method: "anything/not/existing", params: {})
    assert_same(RubyLsp::VOID, result.response)
  end

  private

  def with_uninstalled_rubocop(&block)
    rubocop_paths = $LOAD_PATH.select { |path| path.include?("gems/rubocop") }
    rubocop_paths.each { |path| $LOAD_PATH.delete(path) }

    $LOADED_FEATURES.delete_if { |path| path.include?("ruby_lsp/requests/support/rubocop_runner") }

    unload_rubocop_runner
    block.call
  ensure
    $LOAD_PATH.unshift(*rubocop_paths)
    unload_rubocop_runner
    require "ruby_lsp/requests/support/rubocop_runner"
  end

  def unload_rubocop_runner
    RubyLsp::Requests::Support.send(:remove_const, :RuboCopRunner)
  rescue NameError
    # Depending on which tests have run prior to this one, `RuboCopRunner` may or may not be defined
  end

  def stub_dependencies(rubocop:, syntax_tree:)
    Singleton.__init__(RubyLsp::DependencyDetector)
    dependencies = {}
    dependencies["syntax_tree"] = "..." if syntax_tree
    dependencies["rubocop"] = "..." if rubocop
    Bundler.locked_gems.stubs(:dependencies).returns(dependencies)
  end
end
